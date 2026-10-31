// ltshim.cpp — implementation of the C API in ltshim.h on top of libtorrent 2.x.
//
// Every entry point catches exceptions so none can unwind into Swift.

#include "ltshim.h"

#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/address.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/announce_entry.hpp>
#include <libtorrent/bencode.hpp>
#include <libtorrent/create_torrent.hpp>
#include <libtorrent/ip_filter.hpp>
#include <libtorrent/error_code.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/peer_info.hpp>
#include <libtorrent/read_resume_data.hpp>
#include <libtorrent/session.hpp>
#include <libtorrent/session_params.hpp>
#include <libtorrent/session_stats.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/socket.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/version.hpp>
#include <libtorrent/write_resume_data.hpp>

#include <cctype>
#include <fnmatch.h>
#include <cerrno>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <map>
#include <memory>
#include <sstream>
#include <string>
#include <system_error>
#include <vector>

namespace fs = std::filesystem;

struct lt_session {
    std::unique_ptr<lt::session> ses;
    std::string state_dir;
    std::map<std::string, lt::torrent_handle> handles;  // id -> handle
    std::map<lt::torrent_handle, std::string> ids;       // handle -> id
    int dht_nodes_index = -1;
    std::int64_t dht_nodes = 0;
    int listen_port = 0;
    bool listening = false;
    int outstanding_resume = 0;
    int sent_index = -1, received_index = -1, incoming_index = -1;
    std::int64_t total_upload = 0, total_download = 0, incoming = 0;
    bool port_mapped = false;
    int external_port = 0;
    std::string incomplete_suffix;
};

namespace {

template <typename Hash>
std::string to_hex(Hash const& hash) {
    std::stringstream out;
    out << hash;
    return out.str();
}

std::string id_for(lt::info_hash_t const& hashes) {
    if (hashes.has_v1()) return to_hex(hashes.v1);
    return to_hex(hashes.get_best());
}

void copy_out(std::string const& text, char* out, size_t length) {
    if (out == nullptr || length == 0) return;
    std::snprintf(out, length, "%s", text.c_str());
}

std::string resume_dir(lt_session const* s) { return s->state_dir + "/resume"; }
std::string resume_path(lt_session const* s, std::string const& id) { return resume_dir(s) + "/" + id + ".fastresume"; }

bool write_file_atomic(std::string const& path, std::vector<char> const& buffer) {
    std::string const temp = path + ".tmp";
    {
        std::ofstream out(temp, std::ios::binary | std::ios::trunc);
        if (!out) return false;
        out.write(buffer.data(), static_cast<std::streamsize>(buffer.size()));
        out.flush();
        if (!out) return false;
    }
    std::error_code ec;
    fs::rename(temp, path, ec);
    return !ec;
}

std::vector<char> read_file(std::string const& path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) return {};
    return std::vector<char>(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
}

lt::settings_pack make_pack(lt_settings const* st) {
    lt::settings_pack pack;
    auto const mask = lt::alert_category::error | lt::alert_category::status | lt::alert_category::storage
        | lt::alert_category::tracker | lt::alert_category::port_mapping | lt::alert_category::performance_warning
        | lt::alert_category::file_progress;
    pack.set_int(lt::settings_pack::alert_mask, static_cast<int>(static_cast<std::uint32_t>(mask)));
    pack.set_int(lt::settings_pack::alert_queue_size, 10000);
    pack.set_int(lt::settings_pack::stop_tracker_timeout, 2);
    // libtorrent bootstraps the DHT from a single router by default; when that one is unreachable a
    // session without peers never joins the DHT. Use well-known public bootstrap routers.
    pack.set_str(lt::settings_pack::dht_bootstrap_nodes,
                 "dht.libtorrent.org:25401,router.bittorrent.com:6881,"
                 "dht.transmissionbt.com:6881,dht.aelitis.com:6881");
    if (st == nullptr) return pack;
    if (st->listen_interfaces && *st->listen_interfaces) pack.set_str(lt::settings_pack::listen_interfaces, st->listen_interfaces);
    if (st->user_agent && *st->user_agent) pack.set_str(lt::settings_pack::user_agent, st->user_agent);
    if (st->peer_fingerprint && *st->peer_fingerprint) pack.set_str(lt::settings_pack::peer_fingerprint, st->peer_fingerprint);
    pack.set_int(lt::settings_pack::download_rate_limit, std::max(0, st->download_rate_limit));
    pack.set_int(lt::settings_pack::upload_rate_limit, std::max(0, st->upload_rate_limit));
    if (st->connections_limit > 0) pack.set_int(lt::settings_pack::connections_limit, st->connections_limit);
    if (st->active_downloads != 0) pack.set_int(lt::settings_pack::active_downloads, st->active_downloads);
    if (st->active_seeds != 0) pack.set_int(lt::settings_pack::active_seeds, st->active_seeds);
    if (st->active_limit != 0) pack.set_int(lt::settings_pack::active_limit, st->active_limit);
    pack.set_bool(lt::settings_pack::enable_dht, st->enable_dht);
    pack.set_bool(lt::settings_pack::enable_lsd, st->enable_lsd);
    pack.set_bool(lt::settings_pack::enable_upnp, st->enable_upnp);
    pack.set_bool(lt::settings_pack::enable_natpmp, st->enable_natpmp);
    return pack;
}

std::string register_handle(lt_session* s, lt::torrent_handle const& handle) {
    std::string id = id_for(handle.info_hashes());
    s->handles[id] = handle;
    s->ids[handle] = id;
    return id;
}

lt::torrent_handle find_handle(lt_session* s, char const* id) {
    if (s == nullptr || id == nullptr) return {};
    auto it = s->handles.find(id);
    if (it == s->handles.end()) return {};
    return it->second;
}

std::string id_of_handle(lt_session* s, lt::torrent_handle const& handle) {
    auto it = s->ids.find(handle);
    return it == s->ids.end() ? std::string() : it->second;
}

void request_resume(lt_session* s, lt::torrent_handle const& handle, lt::resume_data_flags_t flags) {
    if (!handle.is_valid()) return;
    handle.save_resume_data(flags);
    s->outstanding_resume++;
}

void write_resume(lt_session* s, lt::save_resume_data_alert const* alert) {
    std::string const id = id_of_handle(s, alert->handle);
    if (id.empty()) return;  // removed meanwhile; don't resurrect it
    write_file_atomic(resume_path(s, id), lt::write_resume_data_buf(alert->params));
}

bool ends_with(std::string const& text, std::string const& suffix) {
    return !suffix.empty() && text.size() > suffix.size()
        && text.compare(text.size() - suffix.size(), suffix.size(), suffix) == 0;
}

bool file_exists(std::string const& path) {
    std::error_code ec;
    return fs::exists(path, ec);
}

// Gives every file that isn't on disk yet the incomplete suffix (".!ut").
void mark_incomplete_files(lt_session* s, lt::torrent_handle const& handle) {
    if (s->incomplete_suffix.empty()) return;
    auto const ti = handle.torrent_file();
    if (!ti) return;
    std::string const save = handle.status(lt::torrent_handle::query_save_path).save_path;
    lt::file_storage const& files = ti->files();
    for (lt::file_index_t const index : files.file_range()) {
        if (files.pad_file_at(index)) continue;
        std::string const path = files.file_path(index);
        if (ends_with(path, s->incomplete_suffix) || file_exists(save + "/" + path)) continue;
        handle.rename_file(index, path + s->incomplete_suffix);
    }
}

void unmark_file(lt_session* s, lt::torrent_handle const& handle, lt::file_index_t index) {
    auto const ti = handle.torrent_file();
    if (!ti || s->incomplete_suffix.empty()) return;
    std::string const path = ti->files().file_path(index);
    if (ends_with(path, s->incomplete_suffix)) {
        handle.rename_file(index, path.substr(0, path.size() - s->incomplete_suffix.size()));
    }
}

void unmark_finished_files(lt_session* s, lt::torrent_handle const& handle) {
    auto const ti = handle.torrent_file();
    if (!ti || s->incomplete_suffix.empty()) return;
    std::vector<std::int64_t> progress;
    handle.file_progress(progress, lt::torrent_handle::piece_granularity);
    lt::file_storage const& files = ti->files();
    for (lt::file_index_t const index : files.file_range()) {
        auto const i = static_cast<std::size_t>(static_cast<int>(index));
        if (i < progress.size() && progress[i] == files.file_size(index)) unmark_file(s, handle, index);
    }
}

void emit_info(std::string const& name, std::shared_ptr<lt::torrent_info const> const& ti,
               lt::info_hash_t const& hashes, lt_info_cb callback, void* ctx) {
    if (callback == nullptr) return;
    std::string comment, creator;
    std::string const v1 = hashes.has_v1() ? to_hex(hashes.v1) : std::string();
    std::string const v2 = hashes.has_v2() ? to_hex(hashes.v2) : std::string();
    lt_torrent_info info{};
    if (ti) {
        comment = ti->comment();
        creator = ti->creator();
        // Hybrid (v1+v2) torrents carry pad files; users never see those, so leave them out.
        lt::file_storage const& files = ti->files();
        std::int64_t content_size = 0;
        int content_files = 0;
        for (lt::file_index_t const index : files.file_range()) {
            if (files.pad_file_at(index)) continue;
            content_size += files.file_size(index);
            ++content_files;
        }
        info.total_size = content_size;
        info.creation_date = static_cast<std::int64_t>(ti->creation_date());
        info.piece_length = ti->piece_length();
        info.num_pieces = ti->num_pieces();
        info.num_files = content_files;
        info.is_private = ti->priv();
        info.has_metadata = true;
    }
    std::string const display = (name.empty() && ti) ? ti->name() : name;
    info.name = display.c_str();
    info.comment = comment.c_str();
    info.creator = creator.c_str();
    info.info_hash_v1 = v1.c_str();
    info.info_hash_v2 = v2.c_str();
    callback(ctx, &info);
}

void emit_files(std::shared_ptr<lt::torrent_info const> const& ti, std::vector<std::int64_t> const& progress,
                std::vector<lt::download_priority_t> const& priorities, lt_file_cb callback, void* ctx) {
    if (!ti || callback == nullptr) return;
    lt::file_storage const& files = ti->files();
    for (lt::file_index_t const index : files.file_range()) {
        if (files.pad_file_at(index)) continue;
        int const i = static_cast<int>(index);
        std::string const path = files.file_path(index);
        lt_file_entry entry{};
        entry.path = path.c_str();
        entry.size = files.file_size(index);
        entry.downloaded = i < static_cast<int>(progress.size()) ? progress[static_cast<std::size_t>(i)] : 0;
        entry.priority = i < static_cast<int>(priorities.size())
            ? static_cast<int>(static_cast<std::uint8_t>(priorities[static_cast<std::size_t>(i)]))
            : 4;
        entry.index = i;
        callback(ctx, &entry);
    }
}

void emit_status(lt_session* s, lt::torrent_status const& st, lt_callbacks const* cb, void* ctx) {
    std::string id = id_of_handle(s, st.handle);
    if (id.empty()) id = id_for(st.info_hashes);
    std::string const error = st.errc ? st.errc.message() : std::string();
    lt_torrent_status out{};
    out.id = id.c_str();
    out.name = st.name.c_str();
    out.save_path = st.save_path.c_str();
    out.current_tracker = st.current_tracker.c_str();
    out.error = error.c_str();
    out.state = static_cast<int>(st.state);
    out.paused = static_cast<bool>(st.flags & lt::torrent_flags::paused);
    out.auto_managed = static_cast<bool>(st.flags & lt::torrent_flags::auto_managed);
    out.has_metadata = st.has_metadata;
    out.is_seeding = st.is_seeding;
    out.is_finished = st.is_finished;
    out.has_incoming = st.has_incoming;
    out.moving_storage = st.moving_storage;
    out.progress = st.progress;
    out.total_wanted = st.total_wanted;
    out.total_wanted_done = st.total_wanted_done;
    out.all_time_download = st.all_time_download;
    out.all_time_upload = st.all_time_upload;
    out.download_rate = st.download_payload_rate;
    out.upload_rate = st.upload_payload_rate;
    out.num_seeds = st.num_seeds;
    out.num_peers = st.num_peers;
    out.num_complete = st.num_complete;
    out.num_incomplete = st.num_incomplete;
    out.distributed_copies = st.distributed_copies;
    out.queue_position = static_cast<int>(st.queue_position);
    out.added_time = static_cast<std::int64_t>(st.added_time);
    out.completed_time = static_cast<std::int64_t>(st.completed_time);
    out.active_seconds = static_cast<std::int64_t>(std::chrono::duration_cast<std::chrono::seconds>(st.active_duration).count());
    out.seeding_seconds = static_cast<std::int64_t>(std::chrono::duration_cast<std::chrono::seconds>(st.seeding_duration).count());
    out.num_pieces = st.num_pieces;
    cb->on_status(ctx, &out);
}

// libtorrent listens on every local address (loopback, link-local, VPN tunnels, AirDrop) and
// announces from each listen socket, skipping the ones that can't reach a tracker. Those skips,
// the per-socket "sending announce" chatter and LSD failing on loopback are not worth a log line.
bool is_noise(lt::alert const* a) {
    if (auto const* error = lt::alert_cast<lt::tracker_error_alert>(a)) return error->error == lt::errors::announce_skipped;
    if (lt::alert_cast<lt::tracker_announce_alert>(a)) return true;
    if (auto const* lsd = lt::alert_cast<lt::lsd_error_alert>(a)) {
        lt::address const local = lsd->local_address;
        return local.is_loopback() || (local.is_v6() && local.to_v6().is_link_local());
    }
    return false;
}

void log_alert(lt_session* s, lt::alert* a, lt_callbacks const* cb, void* ctx) {
    if (cb == nullptr || cb->on_log == nullptr) return;
    auto const category = a->category();
    auto const interesting = lt::alert_category::error | lt::alert_category::tracker | lt::alert_category::storage
        | lt::alert_category::port_mapping | lt::alert_category::performance_warning;
    if (!(category & interesting) || is_noise(a)) return;
    int level = 0;
    if (category & lt::alert_category::error) level = 2;
    else if (category & lt::alert_category::performance_warning) level = 1;
    std::string id;
    if (auto const* ta = dynamic_cast<lt::torrent_alert const*>(a)) id = id_of_handle(s, ta->handle);
    std::string const message = a->message();
    cb->on_log(ctx, id.c_str(), level, message.c_str());
}

void handle_alert(lt_session* s, lt::alert* a, lt_callbacks const* cb, void* ctx) {
    if (auto const* updates = lt::alert_cast<lt::state_update_alert>(a)) {
        if (cb && cb->on_status) {
            for (lt::torrent_status const& st : updates->status) emit_status(s, st, cb, ctx);
        }
        return;
    }
    if (auto const* stats = lt::alert_cast<lt::session_stats_alert>(a)) {
        auto const counters = stats->counters();
        auto const read = [&](int index, std::int64_t& out) {
            if (index >= 0 && index < static_cast<int>(counters.size())) out = counters[index];
        };
        read(s->dht_nodes_index, s->dht_nodes);
        read(s->sent_index, s->total_upload);
        read(s->received_index, s->total_download);
        read(s->incoming_index, s->incoming);
        return;
    }
    if (auto const* saved = lt::alert_cast<lt::save_resume_data_alert>(a)) {
        if (s->outstanding_resume > 0) s->outstanding_resume--;
        write_resume(s, saved);
        return;
    }
    if (lt::alert_cast<lt::save_resume_data_failed_alert>(a)) {
        if (s->outstanding_resume > 0) s->outstanding_resume--;
        return;  // usually "not modified"; nothing to do
    }
    if (auto const* listening = lt::alert_cast<lt::listen_succeeded_alert>(a)) {
        s->listening = true;
        if (listening->socket_type == lt::socket_type_t::tcp) s->listen_port = listening->port;
    }
    if (auto const* mapped = lt::alert_cast<lt::portmap_alert>(a)) {
        s->port_mapped = true;
        s->external_port = mapped->external_port;
    }
    if (auto const* completed = lt::alert_cast<lt::file_completed_alert>(a)) {
        unmark_file(s, completed->handle, completed->index);
        return;
    }
    if (auto const* renamed = lt::alert_cast<lt::file_renamed_alert>(a)) {
        request_resume(s, renamed->handle, lt::torrent_handle::save_info_dict);
    }
    if (auto const* moved = lt::alert_cast<lt::storage_moved_alert>(a)) {
        std::string const id = id_of_handle(s, moved->handle);
        if (!id.empty() && cb && cb->on_moved) cb->on_moved(ctx, id.c_str(), moved->storage_path(), "");
        request_resume(s, moved->handle, lt::torrent_handle::save_info_dict);
    }
    if (auto const* failed = lt::alert_cast<lt::storage_moved_failed_alert>(a)) {
        std::string const id = id_of_handle(s, failed->handle);
        std::string const message = failed->error.message();
        if (!id.empty() && cb && cb->on_moved) cb->on_moved(ctx, id.c_str(), failed->file_path(), message.c_str());
    }
    if (auto const* finished = lt::alert_cast<lt::torrent_finished_alert>(a)) {
        std::string const id = id_of_handle(s, finished->handle);
        if (!id.empty()) {
            unmark_finished_files(s, finished->handle);
            if (cb && cb->on_finished) cb->on_finished(ctx, id.c_str());
            request_resume(s, finished->handle, lt::torrent_handle::save_info_dict);
        }
    }
    if (auto const* metadata = lt::alert_cast<lt::metadata_received_alert>(a)) {
        std::string const id = id_of_handle(s, metadata->handle);
        if (!id.empty()) {
            mark_incomplete_files(s, metadata->handle);
            if (cb && cb->on_metadata) cb->on_metadata(ctx, id.c_str());
            request_resume(s, metadata->handle, lt::torrent_handle::save_info_dict);
        }
    }
    if (auto const* removed = lt::alert_cast<lt::torrent_removed_alert>(a)) {
        std::string const id = id_for(removed->info_hashes);
        if (cb && cb->on_removed) cb->on_removed(ctx, id.c_str());
        return;
    }
    log_alert(s, a, cb, ctx);
}

int add_common(lt_session* s, lt::add_torrent_params params, lt_add_params const* p,
               char* id_out, size_t id_len, char* error_out, size_t error_len) {
    lt::info_hash_t const hashes = params.ti ? params.ti->info_hashes() : params.info_hashes;
    std::string const expected = id_for(hashes);
    if (s->handles.count(expected) > 0) {
        copy_out(expected, id_out, id_len);
        copy_out("This torrent is already in the list.", error_out, error_len);
        return LT_ADD_DUPLICATE;
    }
    if (p != nullptr && p->save_path != nullptr) params.save_path = p->save_path;
    if (p != nullptr && !p->start) {
        params.flags &= ~lt::torrent_flags::auto_managed;
        params.flags |= lt::torrent_flags::paused;
    } else {
        params.flags |= lt::torrent_flags::auto_managed;
        params.flags &= ~lt::torrent_flags::paused;
    }
    if (p != nullptr && p->skip_hash_check) params.flags |= lt::torrent_flags::seed_mode;
    if (p != nullptr && p->preallocate) params.storage_mode = lt::storage_mode_allocate;
    if (params.ti && !s->incomplete_suffix.empty() && !(params.flags & lt::torrent_flags::seed_mode)) {
        lt::file_storage const& files = params.ti->files();
        for (lt::file_index_t const index : files.file_range()) {
            if (files.pad_file_at(index)) continue;
            std::string const path = files.file_path(index);
            if (!file_exists(params.save_path + "/" + path)) params.renamed_files[index] = path + s->incomplete_suffix;
        }
    }
    if (p != nullptr && p->file_priorities != nullptr && p->file_priority_count > 0) {
        params.file_priorities.clear();
        for (int i = 0; i < p->file_priority_count; ++i) {
            params.file_priorities.push_back(lt::download_priority_t(static_cast<std::uint8_t>(p->file_priorities[i])));
        }
    }
    lt::error_code ec;
    lt::torrent_handle handle = s->ses->add_torrent(std::move(params), ec);
    if (ec || !handle.is_valid()) {
        copy_out(ec ? ec.message() : std::string("libtorrent rejected the torrent"), error_out, error_len);
        return -1;
    }
    std::string const id = register_handle(s, handle);
    copy_out(id, id_out, id_len);
    request_resume(s, handle, lt::torrent_handle::save_info_dict);
    return LT_ADD_OK;
}


std::string trim(std::string text) {
    auto const blank = [](unsigned char c) { return std::isspace(c) != 0; };
    while (!text.empty() && blank(static_cast<unsigned char>(text.back()))) text.pop_back();
    std::size_t start = 0;
    while (start < text.size() && blank(static_cast<unsigned char>(text[start]))) ++start;
    return text.substr(start);
}

// Range files often zero-pad IPv4 octets ("001.002.003.004"), which address parsers reject.
bool parse_filter_address(std::string text, lt::address& out) {
    text = trim(text);
    if (text.find(':') == std::string::npos) {
        std::string cleaned;
        std::size_t start = 0;
        for (int part = 0; part < 4; ++part) {
            std::size_t const dot = text.find('.', start);
            std::string octet = text.substr(start, dot == std::string::npos ? std::string::npos : dot - start);
            std::size_t zeros = 0;
            while (zeros + 1 < octet.size() && octet[zeros] == '0') ++zeros;
            octet = octet.substr(zeros);
            cleaned += (part ? "." : "") + octet;
            if (dot == std::string::npos) { if (part != 3) return false; break; }
            start = dot + 1;
        }
        text = cleaned;
    }
    lt::error_code ec;
    out = lt::make_address(text, ec);
    return !ec;
}

void bencode_string(std::string& out, std::string const& text) {
    out += std::to_string(text.size()) + ":" + text;
}

std::vector<std::string> split_lines(char const* text) {
    std::vector<std::string> lines;
    std::string line;
    std::istringstream in(text ? text : "");
    while (std::getline(in, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        lines.push_back(trim(line));
    }
    return lines;
}

struct create_cancelled {};

}  // namespace

extern "C" {

lt_session* lt_session_create(lt_settings const* settings, char const* state_dir) {
    try {
        auto* s = new lt_session();
        s->state_dir = state_dir ? state_dir : ".";
        std::error_code ec;
        fs::create_directories(resume_dir(s), ec);
        lt::session_params params;
        std::string const state_file = s->state_dir + "/session.dat";
        if (fs::exists(state_file, ec)) {
            std::vector<char> const buffer = read_file(state_file);
            if (!buffer.empty()) {
                try {
                    params = lt::read_session_params(buffer, lt::session_handle::save_dht_state);
                } catch (...) {
                    params = lt::session_params();
                }
            }
        }
        params.settings = make_pack(settings);
        s->ses = std::make_unique<lt::session>(std::move(params));
        s->dht_nodes_index = lt::find_metric_idx("dht.dht_nodes");
        s->sent_index = lt::find_metric_idx("net.sent_payload_bytes");
        s->received_index = lt::find_metric_idx("net.recv_payload_bytes");
        s->incoming_index = lt::find_metric_idx("peer.incoming_connections");
        return s;
    } catch (...) {
        return nullptr;
    }
}

void lt_session_apply_settings(lt_session* s, lt_settings const* settings) {
    if (s == nullptr || !s->ses) return;
    try { s->ses->apply_settings(make_pack(settings)); } catch (...) {}
}

int lt_session_load_resume(lt_session* s) {
    if (s == nullptr || !s->ses) return 0;
    int count = 0;
    try {
        std::error_code ec;
        for (auto const& entry : fs::directory_iterator(resume_dir(s), ec)) {
            if (entry.path().extension() != ".fastresume") continue;
            std::vector<char> const buffer = read_file(entry.path().string());
            if (buffer.empty()) continue;
            lt::error_code lec;
            lt::add_torrent_params params = lt::read_resume_data(buffer, lec);
            if (lec) continue;
            lt::torrent_handle handle = s->ses->add_torrent(std::move(params), lec);
            if (lec || !handle.is_valid()) continue;
            register_handle(s, handle);
            ++count;
        }
    } catch (...) {}
    return count;
}

void lt_session_poll(lt_session* s, lt_callbacks const* callbacks, void* ctx) {
    if (s == nullptr || !s->ses) return;
    try {
        std::vector<lt::alert*> alerts;
        s->ses->pop_alerts(&alerts);
        for (lt::alert* a : alerts) handle_alert(s, a, callbacks, ctx);
        s->ses->post_torrent_updates(lt::torrent_handle::query_name | lt::torrent_handle::query_save_path
            | lt::torrent_handle::query_distributed_copies | lt::torrent_handle::query_accurate_download_counters);
        s->ses->post_session_stats();
        if (callbacks && callbacks->on_session) {
            lt_session_stats stats{};
            stats.dht_nodes = s->dht_nodes;
            stats.listen_port = s->listen_port;
            stats.listening = s->listening;
            stats.total_download = s->total_download;
            stats.total_upload = s->total_upload;
            stats.incoming_connections = s->incoming;
            stats.port_mapped = s->port_mapped;
            stats.external_port = s->external_port;
            stats.paused = s->ses->is_paused();
            callbacks->on_session(ctx, &stats);
        }
    } catch (...) {}
}

void lt_session_save_resume(lt_session* s, bool only_if_modified) {
    if (s == nullptr || !s->ses) return;
    try {
        lt::resume_data_flags_t flags = lt::torrent_handle::save_info_dict;
        if (only_if_modified) flags |= lt::torrent_handle::only_if_modified;
        for (auto const& entry : s->handles) request_resume(s, entry.second, flags);
    } catch (...) {}
}

void lt_session_destroy(lt_session* s, int timeout_ms) {
    if (s == nullptr) return;
    try {
        if (s->ses) {
            s->ses->pause();
            int outstanding = s->outstanding_resume;
            for (auto const& entry : s->handles) {
                if (!entry.second.is_valid()) continue;
                entry.second.save_resume_data(lt::torrent_handle::flush_disk_cache | lt::torrent_handle::save_info_dict);
                ++outstanding;
            }
            auto const deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeout_ms);
            while (outstanding > 0 && std::chrono::steady_clock::now() < deadline) {
                if (s->ses->wait_for_alert(std::chrono::milliseconds(200)) == nullptr) continue;
                std::vector<lt::alert*> alerts;
                s->ses->pop_alerts(&alerts);
                for (lt::alert* a : alerts) {
                    if (auto const* saved = lt::alert_cast<lt::save_resume_data_alert>(a)) {
                        --outstanding;
                        write_resume(s, saved);
                    } else if (lt::alert_cast<lt::save_resume_data_failed_alert>(a)) {
                        --outstanding;
                    }
                }
            }
            try {
                lt::session_params const state = s->ses->session_state(lt::session_handle::save_dht_state);
                write_file_atomic(s->state_dir + "/session.dat", lt::write_session_params_buf(state, lt::session_handle::save_dht_state));
            } catch (...) {}
            s->ses.reset();
        }
    } catch (...) {}
    delete s;
}

int lt_add_torrent_file(lt_session* s, char const* path, lt_add_params const* p,
                        char* id_out, size_t id_len, char* error_out, size_t error_len) {
    if (s == nullptr || !s->ses || path == nullptr) return -1;
    try {
        lt::error_code ec;
        auto ti = std::make_shared<lt::torrent_info>(std::string(path), ec);
        if (ec) { copy_out(ec.message(), error_out, error_len); return -1; }
        lt::add_torrent_params params;
        params.ti = ti;
        return add_common(s, std::move(params), p, id_out, id_len, error_out, error_len);
    } catch (std::exception const& e) {
        copy_out(e.what(), error_out, error_len);
        return -1;
    } catch (...) { return -1; }
}

int lt_add_torrent_data(lt_session* s, char const* data, size_t length, lt_add_params const* p,
                        char* id_out, size_t id_len, char* error_out, size_t error_len) {
    if (s == nullptr || !s->ses || data == nullptr) return -1;
    try {
        lt::error_code ec;
        auto ti = std::make_shared<lt::torrent_info>(lt::span<char const>(data, static_cast<std::ptrdiff_t>(length)), ec, lt::from_span);
        if (ec) { copy_out(ec.message(), error_out, error_len); return -1; }
        lt::add_torrent_params params;
        params.ti = ti;
        return add_common(s, std::move(params), p, id_out, id_len, error_out, error_len);
    } catch (std::exception const& e) {
        copy_out(e.what(), error_out, error_len);
        return -1;
    } catch (...) { return -1; }
}

int lt_add_magnet(lt_session* s, char const* uri, lt_add_params const* p,
                  char* id_out, size_t id_len, char* error_out, size_t error_len) {
    if (s == nullptr || !s->ses || uri == nullptr) return -1;
    try {
        lt::error_code ec;
        lt::add_torrent_params params = lt::parse_magnet_uri(uri, ec);
        if (ec) { copy_out(ec.message(), error_out, error_len); return -1; }
        return add_common(s, std::move(params), p, id_out, id_len, error_out, error_len);
    } catch (std::exception const& e) {
        copy_out(e.what(), error_out, error_len);
        return -1;
    } catch (...) { return -1; }
}

bool lt_torrent_action(lt_session* s, char const* id, int action) {
    try {
        lt::torrent_handle handle = find_handle(s, id);
        if (!handle.is_valid()) return false;
        switch (action) {
        case LT_ACTION_START:
            handle.set_flags(lt::torrent_flags::auto_managed);
            handle.resume();
            break;
        case LT_ACTION_PAUSE:
            handle.unset_flags(lt::torrent_flags::auto_managed);
            handle.pause();
            break;
        case LT_ACTION_FORCE_START:
            handle.unset_flags(lt::torrent_flags::auto_managed);
            handle.resume();
            break;
        case LT_ACTION_RECHECK: handle.force_recheck(); break;
        case LT_ACTION_REANNOUNCE:
            handle.force_reannounce();
            handle.force_dht_announce();
            break;
        case LT_ACTION_QUEUE_UP: handle.queue_position_up(); break;
        case LT_ACTION_QUEUE_DOWN: handle.queue_position_down(); break;
        case LT_ACTION_QUEUE_TOP: handle.queue_position_top(); break;
        case LT_ACTION_QUEUE_BOTTOM: handle.queue_position_bottom(); break;
        default: return false;
        }
        if (action == LT_ACTION_START || action == LT_ACTION_PAUSE || action == LT_ACTION_FORCE_START) {
            request_resume(s, handle, lt::torrent_handle::save_info_dict);
        }
        return true;
    } catch (...) { return false; }
}

bool lt_torrent_remove(lt_session* s, char const* id) {
    try {
        lt::torrent_handle handle = find_handle(s, id);
        if (!handle.is_valid()) return false;
        s->ses->remove_torrent(handle);
        std::error_code ec;
        fs::remove(resume_path(s, id), ec);
        s->ids.erase(handle);
        s->handles.erase(id);
        return true;
    } catch (...) { return false; }
}

bool lt_torrent_set_file_priority(lt_session* s, char const* id, int const* file_indexes, int count, int priority) {
    try {
        lt::torrent_handle handle = find_handle(s, id);
        if (!handle.is_valid() || file_indexes == nullptr) return false;
        auto const value = lt::download_priority_t(static_cast<std::uint8_t>(std::clamp(priority, 0, 7)));
        for (int i = 0; i < count; ++i) handle.file_priority(lt::file_index_t(file_indexes[i]), value);
        request_resume(s, handle, lt::torrent_handle::save_info_dict);
        return true;
    } catch (...) { return false; }
}

bool lt_torrent_set_limits(lt_session* s, char const* id, int download_limit, int upload_limit) {
    try {
        lt::torrent_handle handle = find_handle(s, id);
        if (!handle.is_valid()) return false;
        handle.set_download_limit(download_limit > 0 ? download_limit : -1);
        handle.set_upload_limit(upload_limit > 0 ? upload_limit : -1);
        return true;
    } catch (...) { return false; }
}

bool lt_torrent_add_peer(lt_session* s, char const* id, char const* ip, int port) {
    try {
        lt::torrent_handle handle = find_handle(s, id);
        if (!handle.is_valid() || ip == nullptr || port <= 0 || port > 65535) return false;
        lt::error_code ec;
        lt::address const address = lt::make_address(ip, ec);
        if (ec) return false;
        handle.connect_peer(lt::tcp::endpoint(address, static_cast<std::uint16_t>(port)));
        return true;
    } catch (...) { return false; }
}

char* lt_torrent_magnet(lt_session* s, char const* id) {
    try {
        lt::torrent_handle handle = find_handle(s, id);
        if (!handle.is_valid()) return nullptr;
        std::string const uri = lt::make_magnet_uri(handle);
        if (uri.empty()) return nullptr;
        return strdup(uri.c_str());
    } catch (...) { return nullptr; }
}

bool lt_torrent_info_query(lt_session* s, char const* id, lt_info_cb callback, void* ctx) {
    try {
        lt::torrent_handle handle = find_handle(s, id);
        if (!handle.is_valid()) return false;
        lt::torrent_status const st = handle.status(lt::torrent_handle::query_name);
        emit_info(st.name, handle.torrent_file(), handle.info_hashes(), callback, ctx);
        return true;
    } catch (...) { return false; }
}

bool lt_torrent_files(lt_session* s, char const* id, lt_file_cb callback, void* ctx) {
    try {
        lt::torrent_handle handle = find_handle(s, id);
        if (!handle.is_valid()) return false;
        auto const ti = handle.torrent_file();
        if (!ti) return false;
        std::vector<std::int64_t> progress;
        handle.file_progress(progress, lt::torrent_handle::piece_granularity);
        std::vector<lt::download_priority_t> const priorities = handle.get_file_priorities();
        emit_files(ti, progress, priorities, callback, ctx);
        return true;
    } catch (...) { return false; }
}

bool lt_torrent_peers(lt_session* s, char const* id, lt_peer_cb callback, void* ctx) {
    try {
        lt::torrent_handle handle = find_handle(s, id);
        if (!handle.is_valid() || callback == nullptr) return false;
        std::vector<lt::peer_info> peers;
        handle.get_peer_info(peers);
        for (lt::peer_info const& peer : peers) {
            std::string flags;
            if (peer.flags & lt::peer_info::interesting) flags += (peer.flags & lt::peer_info::choked) ? "d" : "D";
            if (peer.flags & lt::peer_info::remote_interested) flags += (peer.flags & lt::peer_info::remote_choked) ? "u" : "U";
            if (peer.flags & (lt::peer_info::rc4_encrypted | lt::peer_info::plaintext_encrypted)) flags += "E";
            if (peer.flags & lt::peer_info::utp_socket) flags += "P";
            if (peer.source & lt::peer_info::pex) flags += "X";
            if (peer.source & lt::peer_info::dht) flags += "H";
            if (peer.source & lt::peer_info::lsd) flags += "L";
            if (peer.source & lt::peer_info::incoming) flags += "I";
            std::string const ip = peer.ip.address().to_string();
            lt_peer_entry entry{};
            entry.ip = ip.c_str();
            entry.client = peer.client.c_str();
            entry.flags = flags.c_str();
            entry.port = peer.ip.port();
            entry.progress = peer.progress;
            entry.download_rate = peer.down_speed;
            entry.upload_rate = peer.up_speed;
            entry.total_download = peer.total_download;
            entry.total_upload = peer.total_upload;
            entry.is_seed = static_cast<bool>(peer.flags & lt::peer_info::seed);
            callback(ctx, &entry);
        }
        return true;
    } catch (...) { return false; }
}

bool lt_torrent_trackers(lt_session* s, char const* id, lt_tracker_cb callback, void* ctx) {
    try {
        lt::torrent_handle handle = find_handle(s, id);
        if (!handle.is_valid() || callback == nullptr) return false;
        auto const now = lt::clock_type::now();
        for (lt::announce_entry const& tracker : handle.trackers()) {
            bool working = false, updating = false, failed = false;
            int seeds = -1, peers = -1, downloaded = -1;
            std::int64_t next = -1;
            std::string error, notice;
            // One endpoint per listen socket and protocol version; sockets that can't reach this
            // tracker are skipped by libtorrent and say nothing about whether the tracker works.
            for (lt::announce_endpoint const& endpoint : tracker.endpoints) {
                if (!endpoint.enabled) continue;
                for (auto const& hash : endpoint.info_hashes) {
                    if (hash.last_error == lt::errors::announce_skipped) continue;
                    if (hash.updating) updating = true;
                    if (hash.fails == 0 && hash.start_sent) working = true;
                    if (hash.last_error && hash.fails > 0) {
                        failed = true;
                        if (error.empty()) error = hash.last_error.message();
                    }
                    if (notice.empty() && !hash.message.empty()) notice = hash.message;
                    seeds = std::max(seeds, hash.scrape_complete);
                    peers = std::max(peers, hash.scrape_incomplete);
                    downloaded = std::max(downloaded, hash.scrape_downloaded);
                    auto const seconds = std::chrono::duration_cast<std::chrono::seconds>(hash.next_announce - now).count();
                    if (seconds > 0 && (next < 0 || seconds < next)) next = static_cast<std::int64_t>(seconds);
                }
            }
            std::string const message = (failed && !working) ? (notice.empty() ? error : notice) : notice;
            lt_tracker_entry entry{};
            entry.url = tracker.url.c_str();
            entry.message = message.c_str();
            entry.tier = static_cast<int>(tracker.tier);
            entry.status = updating ? 2 : (working ? 1 : (failed ? 3 : 0));
            entry.seeds = seeds;
            entry.peers = peers;
            entry.downloaded = downloaded;
            entry.next_announce_seconds = next;
            callback(ctx, &entry);
        }
        return true;
    } catch (...) { return false; }
}

bool lt_inspect_torrent(char const* path, char const* data, size_t length, lt_info_cb info_cb,
                        lt_file_cb file_cb, void* ctx, char* error_out, size_t error_len) {
    try {
        lt::error_code ec;
        std::shared_ptr<lt::torrent_info> ti;
        if (path != nullptr) {
            ti = std::make_shared<lt::torrent_info>(std::string(path), ec);
        } else if (data != nullptr) {
            ti = std::make_shared<lt::torrent_info>(lt::span<char const>(data, static_cast<std::ptrdiff_t>(length)), ec, lt::from_span);
        } else {
            copy_out("Nothing to read.", error_out, error_len);
            return false;
        }
        if (ec) { copy_out(ec.message(), error_out, error_len); return false; }
        emit_info(ti->name(), ti, ti->info_hashes(), info_cb, ctx);
        std::vector<std::int64_t> const progress;
        std::vector<lt::download_priority_t> const priorities;
        emit_files(ti, progress, priorities, file_cb, ctx);
        return true;
    } catch (std::exception const& e) {
        copy_out(e.what(), error_out, error_len);
        return false;
    } catch (...) { return false; }
}

bool lt_inspect_magnet(char const* uri, lt_info_cb info_cb, void* ctx, char* error_out, size_t error_len) {
    try {
        lt::error_code ec;
        lt::add_torrent_params const params = lt::parse_magnet_uri(uri ? uri : "", ec);
        if (ec) { copy_out(ec.message(), error_out, error_len); return false; }
        emit_info(params.name, nullptr, params.info_hashes, info_cb, ctx);
        return true;
    } catch (std::exception const& e) {
        copy_out(e.what(), error_out, error_len);
        return false;
    } catch (...) { return false; }
}

int lt_session_apply_named(lt_session* s, lt_setting_pair const* pairs, int count, char* error_out, size_t error_len) {
    if (s == nullptr || !s->ses || pairs == nullptr) return 0;
    try {
        lt::settings_pack pack;
        int applied = 0;
        std::string rejected;
        for (int i = 0; i < count; ++i) {
            if (pairs[i].name == nullptr || pairs[i].value == nullptr) continue;
            std::string const name = pairs[i].name;
            std::string const value = pairs[i].value;
            int const code = lt::setting_by_name(name);
            bool ok = code >= 0;
            if (ok) {
                switch (code & lt::settings_pack::type_mask) {
                case lt::settings_pack::string_type_base:
                    pack.set_str(code, value);
                    break;
                case lt::settings_pack::int_type_base: {
                    char* end = nullptr;
                    errno = 0;
                    long long const number = std::strtoll(value.c_str(), &end, 10);
                    ok = !value.empty() && end != nullptr && *end == 0 && errno == 0
                        && number >= INT32_MIN && number <= INT32_MAX;
                    if (ok) pack.set_int(code, static_cast<int>(number));
                    break;
                }
                case lt::settings_pack::bool_type_base:
                    if (value == "true" || value == "1" || value == "yes") pack.set_bool(code, true);
                    else if (value == "false" || value == "0" || value == "no") pack.set_bool(code, false);
                    else ok = false;
                    break;
                default:
                    ok = false;
                }
            }
            if (ok) ++applied;
            else rejected += (rejected.empty() ? "" : ", ") + name;
        }
        s->ses->apply_settings(std::move(pack));
        if (!rejected.empty()) copy_out("Not applied: " + rejected, error_out, error_len);
        return applied;
    } catch (std::exception const& e) {
        copy_out(e.what(), error_out, error_len);
        return 0;
    } catch (...) { return 0; }
}

void lt_session_list_settings(lt_session* s, lt_setting_cb callback, void* ctx) {
    if (s == nullptr || !s->ses || callback == nullptr) return;
    try {
        lt::settings_pack const current = s->ses->get_settings();
        lt::settings_pack const defaults = lt::default_settings();
        auto const emit = [&](int code, int type) {
            char const* raw = lt::name_for_setting(code);
            if (raw == nullptr || *raw == 0) return;
            std::string value, fallback;
            switch (type) {
            case 0: value = current.get_str(code); fallback = defaults.get_str(code); break;
            case 1: value = std::to_string(current.get_int(code)); fallback = std::to_string(defaults.get_int(code)); break;
            default:
                value = current.get_bool(code) ? "true" : "false";
                fallback = defaults.get_bool(code) ? "true" : "false";
            }
            lt_setting_info info{};
            info.name = raw;
            info.type = type;
            info.value = value.c_str();
            info.default_value = fallback.c_str();
            callback(ctx, &info);
        };
        for (int i = 0; i < lt::settings_pack::num_string_settings; ++i) emit(lt::settings_pack::string_type_base + i, 0);
        for (int i = 0; i < lt::settings_pack::num_int_settings; ++i) emit(lt::settings_pack::int_type_base + i, 1);
        for (int i = 0; i < lt::settings_pack::num_bool_settings; ++i) emit(lt::settings_pack::bool_type_base + i, 2);
    } catch (...) {}
}


int lt_session_load_ip_filter(lt_session* s, char const* path, char* error_out, size_t error_len) {
    if (s == nullptr || !s->ses) return -1;
    try {
        lt::ip_filter filter;
        if (path == nullptr || *path == 0) {
            s->ses->set_ip_filter(filter);
            return 0;
        }
        std::ifstream in(path);
        if (!in) { copy_out("Couldn't open the filter file.", error_out, error_len); return -1; }
        int ranges = 0, skipped = 0;
        std::string line;
        while (std::getline(in, line)) {
            line = trim(line);
            if (line.empty() || line[0] == '#' || line.rfind("//", 0) == 0) continue;
            std::string from, to;
            std::size_t const comma = line.find(',');
            std::size_t const dash = line.find(" - ");
            if (dash != std::string::npos && comma != std::string::npos && dash < comma) {
                // DAT: "first - last , level , description"; levels above 127 are allowed.
                from = line.substr(0, dash);
                to = line.substr(dash + 3, comma - dash - 3);
                std::size_t const comma2 = line.find(',', comma + 1);
                std::string const level = trim(line.substr(comma + 1, comma2 == std::string::npos ? std::string::npos : comma2 - comma - 1));
                if (!level.empty() && std::atoi(level.c_str()) > 127) continue;
            } else {
                // P2P: "description:first-last"
                std::size_t const colon = line.rfind(':');
                std::size_t const hyphen = line.rfind('-');
                if (colon == std::string::npos || hyphen == std::string::npos || hyphen < colon) { ++skipped; continue; }
                from = line.substr(colon + 1, hyphen - colon - 1);
                to = line.substr(hyphen + 1);
            }
            lt::address first, last;
            if (!parse_filter_address(from, first) || !parse_filter_address(to, last) || first.is_v4() != last.is_v4()
                || last < first) {
                ++skipped;
                continue;
            }
            filter.add_rule(first, last, lt::ip_filter::blocked);
            ++ranges;
        }
        s->ses->set_ip_filter(filter);
        if (ranges == 0) copy_out(skipped ? "No usable ranges in the filter file." : "The filter file is empty.", error_out, error_len);
        return ranges;
    } catch (std::exception const& e) {
        copy_out(e.what(), error_out, error_len);
        return -1;
    } catch (...) { return -1; }
}

void lt_session_set_paused(lt_session* s, bool paused) {
    if (s == nullptr || !s->ses) return;
    try {
        if (paused) s->ses->pause();
        else s->ses->resume();
    } catch (...) {}
}

void lt_session_set_incomplete_suffix(lt_session* s, char const* suffix) {
    if (s == nullptr) return;
    s->incomplete_suffix = suffix ? suffix : "";
}

bool lt_torrent_get_props(lt_session* s, char const* id, lt_torrent_props* out) {
    try {
        lt::torrent_handle handle = find_handle(s, id);
        if (!handle.is_valid() || out == nullptr) return false;
        lt_torrent_props p{};
        p.download_limit = std::max(0, handle.download_limit());
        p.upload_limit = std::max(0, handle.upload_limit());
        int const connections = handle.max_connections();
        int const uploads = handle.max_uploads();
        p.max_connections = (connections <= 0 || connections >= (1 << 24) - 1) ? 0 : connections;
        p.max_uploads = (uploads <= 0 || uploads >= (1 << 24) - 1) ? 0 : uploads;
        auto const flags = handle.flags();
        p.disable_dht = static_cast<bool>(flags & lt::torrent_flags::disable_dht);
        p.disable_pex = static_cast<bool>(flags & lt::torrent_flags::disable_pex);
        p.disable_lsd = static_cast<bool>(flags & lt::torrent_flags::disable_lsd);
        p.super_seeding = static_cast<bool>(flags & lt::torrent_flags::super_seeding);
        p.sequential = static_cast<bool>(flags & lt::torrent_flags::sequential_download);
        *out = p;
        return true;
    } catch (...) { return false; }
}

bool lt_torrent_set_props(lt_session* s, char const* id, lt_torrent_props const* p) {
    try {
        lt::torrent_handle handle = find_handle(s, id);
        if (!handle.is_valid() || p == nullptr) return false;
        handle.set_download_limit(p->download_limit > 0 ? p->download_limit : -1);
        handle.set_upload_limit(p->upload_limit > 0 ? p->upload_limit : -1);
        handle.set_max_connections(p->max_connections > 0 ? p->max_connections : -1);
        handle.set_max_uploads(p->max_uploads > 0 ? p->max_uploads : -1);
        auto const apply = [&](bool on, lt::torrent_flags_t flag) {
            if (on) handle.set_flags(flag);
            else handle.unset_flags(flag);
        };
        apply(p->disable_dht, lt::torrent_flags::disable_dht);
        apply(p->disable_pex, lt::torrent_flags::disable_pex);
        apply(p->disable_lsd, lt::torrent_flags::disable_lsd);
        apply(p->super_seeding, lt::torrent_flags::super_seeding);
        apply(p->sequential, lt::torrent_flags::sequential_download);
        request_resume(s, handle, lt::torrent_handle::save_info_dict);
        return true;
    } catch (...) { return false; }
}

bool lt_torrent_set_trackers(lt_session* s, char const* id, char const* const* urls, int const* tiers, int count) {
    try {
        lt::torrent_handle handle = find_handle(s, id);
        if (!handle.is_valid() || (urls == nullptr && count > 0)) return false;
        std::vector<lt::announce_entry> list;
        for (int i = 0; i < count; ++i) {
            if (urls[i] == nullptr || *urls[i] == 0) continue;
            lt::announce_entry entry(urls[i]);
            entry.tier = static_cast<std::uint8_t>(std::clamp(tiers ? tiers[i] : 0, 0, 255));
            list.push_back(entry);
        }
        handle.replace_trackers(list);
        if (!list.empty()) handle.force_reannounce();
        request_resume(s, handle, lt::torrent_handle::save_info_dict);
        return true;
    } catch (...) { return false; }
}

bool lt_torrent_clear_peers(lt_session* s, char const* id) {
    try {
        lt::torrent_handle handle = find_handle(s, id);
        if (!handle.is_valid()) return false;
        handle.clear_peers();
        return true;
    } catch (...) { return false; }
}

bool lt_torrent_move_storage(lt_session* s, char const* id, char const* path) {
    try {
        lt::torrent_handle handle = find_handle(s, id);
        if (!handle.is_valid() || path == nullptr || *path == 0) return false;
        handle.move_storage(path, lt::move_flags_t::dont_replace);
        return true;
    } catch (...) { return false; }
}


bool lt_torrent_export(lt_session* s, char const* id, char const* path, char* error_out, size_t error_len) {
    try {
        lt::torrent_handle handle = find_handle(s, id);
        if (!handle.is_valid() || path == nullptr) return false;
        auto const ti = handle.torrent_file();
        if (!ti) { copy_out("The torrent has no metadata yet.", error_out, error_len); return false; }
        // A .torrent is a dictionary with sorted keys; the info dictionary is copied byte for byte
        // so the info-hash stays the same.
        std::vector<lt::announce_entry> const trackers = handle.trackers();
        std::string out = "d";
        if (!trackers.empty()) {
            bencode_string(out, "announce");
            bencode_string(out, trackers.front().url);
            bencode_string(out, "announce-list");
            out += "l";
            int tier = -1;
            for (auto const& tracker : trackers) {
                if (tracker.tier != tier) {
                    if (tier >= 0) out += "e";
                    out += "l";
                    tier = tracker.tier;
                }
                bencode_string(out, tracker.url);
            }
            out += "ee";
        }
        if (!ti->comment().empty()) { bencode_string(out, "comment"); bencode_string(out, ti->comment()); }
        if (!ti->creator().empty()) { bencode_string(out, "created by"); bencode_string(out, ti->creator()); }
        if (ti->creation_date() > 0) out += "13:creation datei" + std::to_string(ti->creation_date()) + "e";
        bencode_string(out, "info");
        auto const info = ti->info_section();
        out.append(info.data(), static_cast<std::size_t>(info.size()));
        out += "e";
        if (!write_file_atomic(path, std::vector<char>(out.begin(), out.end()))) {
            copy_out("Couldn't write the .torrent file.", error_out, error_len);
            return false;
        }
        return true;
    } catch (std::exception const& e) {
        copy_out(e.what(), error_out, error_len);
        return false;
    } catch (...) { return false; }
}


int lt_create_torrent(lt_create_params const* p, char const* output_path, lt_create_progress_cb progress,
                      void* ctx, char* id_out, size_t id_len, char* error_out, size_t error_len) {
    if (p == nullptr || p->source_path == nullptr || output_path == nullptr) return -1;
    try {
        std::string const source = fs::path(p->source_path).lexically_normal().string();
        std::string root = source;
        while (root.size() > 1 && root.back() == '/') root.pop_back();
        std::error_code fec;
        if (!fs::exists(root, fec)) { copy_out("The file or folder doesn't exist.", error_out, error_len); return -1; }
        std::vector<std::string> patterns;
        {
            std::string const all = p->skip_patterns ? p->skip_patterns : "";
            std::size_t start = 0;
            while (start <= all.size()) {
                std::size_t const end = all.find(';', start);
                std::string const pattern = trim(all.substr(start, end == std::string::npos ? std::string::npos : end - start));
                if (!pattern.empty()) patterns.push_back(pattern);
                if (end == std::string::npos) break;
                start = end + 1;
            }
        }
        lt::create_flags_t flags{};
        if (p->format == 1) flags |= lt::create_torrent::v1_only;
        if (p->format == 2) flags |= lt::create_torrent::v2_only;
        lt::file_storage files;
        lt::add_files(files, root, [&](std::string const& path) {
            std::string const name = fs::path(path).filename().string();
            if (name.empty() || name == ".DS_Store") return false;
            for (auto const& pattern : patterns) {
                if (fnmatch(pattern.c_str(), name.c_str(), 0) == 0) return false;
            }
            return true;
        }, flags);
        if (files.num_files() == 0) { copy_out("There are no files to put in the torrent.", error_out, error_len); return -1; }
        int const piece_size = p->piece_size > 0 ? p->piece_size : 0;
        if (piece_size > 0 && (piece_size < 16 * 1024 || (piece_size & (piece_size - 1)) != 0)) {
            copy_out("The piece size must be a power of two of at least 16 KiB.", error_out, error_len);
            return -1;
        }
        lt::create_torrent t(files, piece_size, flags);
        int tier = 0;
        bool tier_used = false;
        for (std::string const& line : split_lines(p->trackers)) {
            if (line.empty()) {
                if (tier_used) { ++tier; tier_used = false; }
                continue;
            }
            t.add_tracker(line, tier);
            tier_used = true;
        }
        for (std::string const& line : split_lines(p->web_seeds)) {
            if (!line.empty()) t.add_url_seed(line);
        }
        if (p->comment && *p->comment) t.set_comment(p->comment);
        t.set_creator(p->creator && *p->creator ? p->creator : "Freshet");
        t.set_priv(p->is_private);
        int const total = t.num_pieces();
        int done = 0;
        std::string const parent = fs::path(root).parent_path().string();
        lt::error_code ec;
        try {
            lt::set_piece_hashes(t, parent.empty() ? "." : parent, [&](lt::piece_index_t) {
                ++done;
                if (progress && !progress(ctx, done, total)) throw create_cancelled{};
            }, ec);
        } catch (create_cancelled const&) {
            copy_out("Cancelled.", error_out, error_len);
            return -2;
        }
        if (ec) { copy_out(ec.message(), error_out, error_len); return -1; }
        std::vector<char> buffer;
        lt::bencode(std::back_inserter(buffer), t.generate());
        if (!write_file_atomic(output_path, buffer)) { copy_out("Couldn't write the .torrent file.", error_out, error_len); return -1; }
        lt::error_code tec;
        lt::torrent_info const ti(lt::span<char const>(buffer.data(), static_cast<std::ptrdiff_t>(buffer.size())), tec, lt::from_span);
        if (!tec) copy_out(id_for(ti.info_hashes()), id_out, id_len);
        return 0;
    } catch (std::exception const& e) {
        copy_out(e.what(), error_out, error_len);
        return -1;
    } catch (...) { return -1; }
}

void lt_free(void* pointer) { std::free(pointer); }

const char* lt_version(void) { return LIBTORRENT_VERSION; }

}  // extern "C"
