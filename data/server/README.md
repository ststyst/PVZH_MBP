# 服务器/运行优化配置

文件：`data/server/server_config.json`

## 当前状态

- **所有参数均为预留，暂未接入代码**。它们用于未来专用服务器/LAN 主机，当前不会影响单机规则。
- 玩法内容（牌组上限、英雄生命、抽牌等）仍由 `data/modes/default_mode.json` 管理。

## network

| 参数 | 默认 | 功能 |
|---|---|---|
| `bind_host` | `0.0.0.0` | 服务器监听地址；`0.0.0.0` 表示所有网卡 |
| `port` | `45770` | 游戏 ENet 端口 |
| `max_players` | `8` | 最大同时连接玩家数 |
| `tick_rate_hz` | `20` | 服务器逻辑/广播更新频率 |
| `connection_timeout_seconds` | `10` | 建立连接的超时时间 |
| `keepalive_interval_seconds` | `2` | 心跳间隔，用于检测掉线 |
| `max_packet_bytes` | `65536` | 单条消息最大字节数，防止异常大包 |

## protocol

| 参数 | 默认 | 功能 |
|---|---|---|
| `protocol_version` | `1` | 联机协议版本；不一致时拒绝连接 |
| `allow_mods` | `false` | 是否允许模组内容联机；当前固定关闭 |
| `require_official_card_set` | `true` | 是否强制官方卡牌集合 |
| `card_set_hash` | `""` | 官方卡表哈希；空表示启动时由服务器计算 |
| `mode_file` | `res://data/modes/default_mode.json` | 服务器使用的玩法配置文件 |
| `min_client_version` | `0.1.0` | 允许连接的最低客户端版本 |

## match

| 参数 | 默认 | 功能 |
|---|---|---|
| `command_rate_limit_per_second` | `10` | 单个玩家每秒最多接受的命令数 |
| `max_commands_per_turn` | `100` | 单个回合内单玩家命令上限 |
| `snapshot_interval_seconds` | `1` | 全量快照最小间隔；期间用事件增量 |
| `effect_resolution_limit` | `100` | 单次出牌/战斗行为允许的连锁事件上限；超限强制结束连锁 || `reconnect_grace_seconds` | `30` | 断线后保留座位的宽限时间（预留） |
| `surrender_timeout_seconds` | `120` | 投降/超时判定的等待时间（预留） |

## security

| 参数 | 默认 | 功能 |
|---|---|---|
| `max_login_attempts_per_minute` | `10` | 单 IP 每分钟登录尝试上限 |
| `token_ttl_seconds` | `3600` | 登录/重连 token 有效期 |
| `log_commands` | `false` | 是否记录每条客户端命令（用于排查/审计） |

## persistence

| 参数 | 默认 | 功能 |
|---|---|---|
| `save_profiles` | `false` | 是否持久化服务器玩家档案；当前不做 |
| `profile_store` | `user://server_profiles.json` | 服务器档案存储路径（预留） |
| `save_interval_seconds` | `30` | 自动保存间隔 |

## logging

| 参数 | 默认 | 功能 |
|---|---|---|
| `level` | `info` | 日志级别：debug / info / warn / error |
| `log_battles` | `true` | 是否记录对局开始/结束摘要 |
| `log_commands` | `false` | 是否记录命令明细（与 security 中同名项一致） |
| `log_dir` | `user://logs/server` | 服务器日志目录 |

## server

| 参数 | 默认 | 功能 |
|---|---|---|
| `name` | `Card Arena Server` | 局域网发现/服务器列表显示名 |
| `motd` | `""` | 登录后公告文本 |
| `region` | `lan` | 区域标识（lan / cn / asia 等） |
| `max_concurrent_matches` | `32` | 服务器同时进行的对局上限 |
