// ltshim.h — a small C API over libtorrent-rasterbar 2.x.
//
// Swift imports this header directly. All C++ (libtorrent, Boost, OpenSSL) stays in
// ltshim.cpp, so no C++ type ever crosses into Swift. Strings handed to callbacks are
// only valid for the duration of the callback; copy them if you keep them.
#ifndef FRESHET_LTSHIM_H
#define FRESHET_LTSHIM_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct lt_session lt_session;

// Session-wide settings. String fields may be NULL to keep libtorrent's default.
typedef struct lt_settings {
    const char *listen_interfaces;   // e.g. "0.0.0.0:6881,[::]:6881"
    const char *user_agent;
    const char *peer_fingerprint;    // e.g. "-FR0010-"
    int download_rate_limit;         // bytes per second, 0 = unlimited
    int upload_rate_limit;           // bytes per second, 0 = unlimited
    int connections_limit;           // 0 = keep default
    int active_downloads;            // 0 = keep default, -1 = unlimited
    int active_seeds;
    int active_limit;
    bool enable_dht;
    bool enable_lsd;
    bool enable_upnp;
    bool enable_natpmp;
} lt_settings;

typedef struct lt_add_params {
    const char *save_path;
    bool start;                      // false = add stopped
    bool skip_hash_check;            // trust files already on disk (seed mode)
    const int *file_priorities;      // optional, one entry per file index
    int file_priority_count;
    bool preallocate;                // allocate full files up front instead of sparse files
} lt_add_params;

typedef struct lt_torrent_status {
    const char *id;                  // hex info-hash (v1 when present, else truncated v2)
    const char *name;
    const char *save_path;
    const char *current_tracker;
    const char *error;               // empty string when there is no error
    int state;                       // libtorrent torrent_status::state_t
    bool paused;
    bool auto_managed;
    bool has_metadata;
    bool is_seeding;
    bool is_finished;
    bool has_incoming;
    bool moving_storage;
    float progress;                  // 0...1 of the wanted data
    int64_t total_wanted;
    int64_t total_wanted_done;
    int64_t all_time_download;
    int64_t all_time_upload;
    int download_rate;               // payload bytes per second
    int upload_rate;
    int num_seeds;                   // connected seeds
    int num_peers;                   // connected peers, seeds included
    int num_complete;                // seeds in the swarm, -1 when unknown
    int num_incomplete;              // downloaders in the swarm, -1 when unknown
    float distributed_copies;        // availability, -1 when unknown
    int queue_position;              // -1 when not queued
    int64_t added_time;              // unix seconds
    int64_t completed_time;          // unix seconds, 0 when not completed
    int64_t active_seconds;
    int64_t seeding_seconds;
    int num_pieces;                  // pieces we have
} lt_torrent_status;

typedef struct lt_session_stats {
    int64_t dht_nodes;
    int listen_port;                 // 0 until a listen socket is open
    bool listening;
    int64_t total_download;          // payload bytes received since the session started
    int64_t total_upload;            // payload bytes sent since the session started
    int64_t incoming_connections;    // peers that connected to us since the session started
    bool port_mapped;                // UPnP or NAT-PMP mapped the listening port
    int external_port;               // the mapped port, 0 when unknown
    bool paused;                     // the whole session is paused
} lt_session_stats;

typedef struct lt_file_entry {
    const char *path;
    int64_t size;
    int64_t downloaded;
    int priority;                    // 0 = skip, 1 = low, 4 = normal, 7 = high
    int index;                       // libtorrent file index
} lt_file_entry;

typedef struct lt_peer_entry {
    const char *ip;
    const char *client;
    const char *flags;               // peer flag letters (D, U, E, P, …)
    int port;
    float progress;
    int download_rate;
    int upload_rate;
    int64_t total_download;
    int64_t total_upload;
    bool is_seed;
} lt_peer_entry;

typedef struct lt_tracker_entry {
    const char *url;
    const char *message;
    int tier;
    int status;                      // 0 idle, 1 working, 2 updating, 3 error
    int seeds;                       // -1 unknown
    int peers;                       // -1 unknown
    int downloaded;                  // -1 unknown
    int64_t next_announce_seconds;   // -1 unknown
} lt_tracker_entry;

typedef struct lt_torrent_info {
    const char *name;
    const char *comment;
    const char *creator;
    const char *info_hash_v1;        // empty when absent
    const char *info_hash_v2;        // empty when absent
    int64_t total_size;
    int64_t creation_date;           // unix seconds, 0 when unknown
    int piece_length;
    int num_pieces;
    int num_files;
    bool is_private;
    bool has_metadata;
} lt_torrent_info;

typedef struct lt_callbacks {
    void (*on_status)(void *ctx, const lt_torrent_status *status);
    void (*on_removed)(void *ctx, const char *id);
    void (*on_finished)(void *ctx, const char *id);
    void (*on_metadata)(void *ctx, const char *id);
    void (*on_log)(void *ctx, const char *id, int level, const char *message);
    void (*on_session)(void *ctx, const lt_session_stats *stats);
    // Storage move finished; error is empty on success.
    void (*on_moved)(void *ctx, const char *id, const char *path, const char *error);
} lt_callbacks;

typedef void (*lt_file_cb)(void *ctx, const lt_file_entry *file);
typedef void (*lt_peer_cb)(void *ctx, const lt_peer_entry *peer);
typedef void (*lt_tracker_cb)(void *ctx, const lt_tracker_entry *tracker);
typedef void (*lt_info_cb)(void *ctx, const lt_torrent_info *info);

// Per-torrent settings shown in the Properties sheet.
typedef struct lt_torrent_props {
    int download_limit;              // bytes per second, 0 = unlimited
    int upload_limit;                // bytes per second, 0 = unlimited
    int max_connections;             // 0 = no limit of its own
    int max_uploads;                 // upload slots, 0 = no limit of its own
    bool disable_dht;
    bool disable_pex;
    bool disable_lsd;
    bool super_seeding;
    bool sequential;
} lt_torrent_props;

// One libtorrent setting by its settings_pack name, value as text ("true"/"false" for switches).
typedef struct lt_setting_pair {
    const char *name;
    const char *value;
} lt_setting_pair;

typedef struct lt_setting_info {
    const char *name;
    int type;                        // 0 text, 1 number, 2 switch
    const char *value;
    const char *default_value;
} lt_setting_info;

typedef void (*lt_setting_cb)(void *ctx, const lt_setting_info *setting);

#define LT_ACTION_START 0
#define LT_ACTION_PAUSE 1
#define LT_ACTION_FORCE_START 2
#define LT_ACTION_RECHECK 3
#define LT_ACTION_REANNOUNCE 4
#define LT_ACTION_QUEUE_UP 5
#define LT_ACTION_QUEUE_DOWN 6
#define LT_ACTION_QUEUE_TOP 7
#define LT_ACTION_QUEUE_BOTTOM 8

#define LT_ADD_OK 0
#define LT_ADD_DUPLICATE 2

// Session lifecycle. state_dir holds one .fastresume file per torrent plus DHT state.
lt_session *lt_session_create(const lt_settings *settings, const char *state_dir);
void lt_session_apply_settings(lt_session *session, const lt_settings *settings);
int lt_session_load_resume(lt_session *session);
void lt_session_poll(lt_session *session, const lt_callbacks *callbacks, void *ctx);
void lt_session_save_resume(lt_session *session, bool only_if_modified);
void lt_session_destroy(lt_session *session, int timeout_ms);

// Settings by libtorrent name, applied after lt_settings. Returns how many were applied; the
// names that were not recognised or not valid are listed in error_out.
int lt_session_apply_named(lt_session *session, const lt_setting_pair *pairs, int count,
                           char *error_out, size_t error_len);
// Every libtorrent setting with its current and default value.
void lt_session_list_settings(lt_session *session, lt_setting_cb callback, void *ctx);
// Loads an ipfilter.dat (DAT) or PeerGuardian (P2P) range file into the session's IP filter,
// replacing the previous one. NULL path clears the filter. Returns the number of blocked ranges, -1 on error.
int lt_session_load_ip_filter(lt_session *session, const char *path, char *error_out, size_t error_len);
// Pauses or resumes every torrent at once without touching their own states (scheduler, transfer cap).
void lt_session_set_paused(lt_session *session, bool paused);
// Suffix added to files until they complete (".!ut"); NULL or "" turns it off for new files.
void lt_session_set_incomplete_suffix(lt_session *session, const char *suffix);

// Adding torrents. Return LT_ADD_OK, LT_ADD_DUPLICATE (id_out holds the existing id),
// or a negative value with a message in error_out.
int lt_add_torrent_file(lt_session *session, const char *path, const lt_add_params *params,
                        char *id_out, size_t id_len, char *error_out, size_t error_len);
int lt_add_torrent_data(lt_session *session, const char *data, size_t length, const lt_add_params *params,
                        char *id_out, size_t id_len, char *error_out, size_t error_len);
int lt_add_magnet(lt_session *session, const char *uri, const lt_add_params *params,
                  char *id_out, size_t id_len, char *error_out, size_t error_len);

// Commands on one torrent. Return false when the id is unknown.
bool lt_torrent_action(lt_session *session, const char *id, int action);
bool lt_torrent_remove(lt_session *session, const char *id);
bool lt_torrent_set_file_priority(lt_session *session, const char *id, const int *file_indexes, int count, int priority);
bool lt_torrent_set_limits(lt_session *session, const char *id, int download_limit, int upload_limit);
// Connect to a peer directly (Add Peer). ip is a numeric IPv4 or IPv6 address.
bool lt_torrent_add_peer(lt_session *session, const char *id, const char *ip, int port);
char *lt_torrent_magnet(lt_session *session, const char *id);  // free with lt_free
bool lt_torrent_get_props(lt_session *session, const char *id, lt_torrent_props *out);
bool lt_torrent_set_props(lt_session *session, const char *id, const lt_torrent_props *props);
// Replaces the tracker list. tiers may be NULL (tier 0 for all).
bool lt_torrent_set_trackers(lt_session *session, const char *id, const char *const *urls, const int *tiers, int count);
bool lt_torrent_clear_peers(lt_session *session, const char *id);
// Moves the torrent's files to a new folder; the result arrives as on_moved.
bool lt_torrent_move_storage(lt_session *session, const char *id, const char *path);
// Writes the torrent's metadata as a .torrent file. False when there is no metadata yet.
bool lt_torrent_export(lt_session *session, const char *id, const char *path, char *error_out, size_t error_len);

// Detail queries for one torrent (synchronous; call for the selected torrent only).
bool lt_torrent_info_query(lt_session *session, const char *id, lt_info_cb callback, void *ctx);
bool lt_torrent_files(lt_session *session, const char *id, lt_file_cb callback, void *ctx);
bool lt_torrent_peers(lt_session *session, const char *id, lt_peer_cb callback, void *ctx);
bool lt_torrent_trackers(lt_session *session, const char *id, lt_tracker_cb callback, void *ctx);

// Read a .torrent (from a path, or from memory when path is NULL) or a magnet link without adding it.
bool lt_inspect_torrent(const char *path, const char *data, size_t length, lt_info_cb info_cb,
                        lt_file_cb file_cb, void *ctx, char *error_out, size_t error_len);
bool lt_inspect_magnet(const char *uri, lt_info_cb info_cb, void *ctx, char *error_out, size_t error_len);

// Creating torrents. Lists are newline-separated; a blank line in trackers starts the next tier.
typedef struct lt_create_params {
    const char *source_path;         // a file or a folder
    const char *trackers;
    const char *web_seeds;
    const char *comment;
    const char *creator;
    const char *skip_patterns;       // ';'-separated file name patterns to leave out, e.g. "*.nfo;Thumbs.db"
    int piece_size;                  // bytes, 0 = automatic
    int format;                      // 0 hybrid (v1 + v2), 1 v1 only, 2 v2 only
    bool is_private;
} lt_create_params;

// Called after each piece is hashed; return false to cancel.
typedef bool (*lt_create_progress_cb)(void *ctx, int pieces_done, int pieces_total);

// Hashes the source and writes a .torrent to output_path (runs on the calling thread; call it
// off the main thread). Returns 0, or -1 with a message, or -2 when cancelled. id_out gets the id
// the engine will use for it.
int lt_create_torrent(const lt_create_params *params, const char *output_path, lt_create_progress_cb progress,
                      void *ctx, char *id_out, size_t id_len, char *error_out, size_t error_len);

void lt_free(void *pointer);
const char *lt_version(void);

#ifdef __cplusplus
}
#endif

#endif
