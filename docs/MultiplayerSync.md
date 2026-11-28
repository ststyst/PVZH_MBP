# 联机同步设计（当前方向）

> 当前状态：战斗引擎/DSL 已支持区域被动、多目标选择、特殊标志物与动画动作 cue；
> 手牌/牌库已使用 `BattleCardInstance`，UI 已支持入场多目标选择；
> ENet 传输基础层（BattleServer/BattleClient/BattleProtocol）已加入；
> 权威对局会话、UI 联机接入、服务器存档仍未实现。

## 决策

- 专用服务器 + 局域网玩家主机权威（host 也运行同一套 BattleServer）
- 双方牌库顺序只在服务器；客户端只知道数量
- 抽牌由服务器发私有事件，把自己的手牌内容发给本人；对手只收到手牌数量
- 阶段计时 `phase_time_limit_seconds=40`，服务器持有 deadline，超时自动结束阶段
- 暂不做服务器存档、断线重连、观战、回放
- 联机不允许模组：握手校验官方卡表/玩法哈希
- 客户端等待服务器确认后再更新状态；动画以服务器动作事件为准，客户端解析动画伪代码
- 特殊标志物公开同步（当前只做数据接口，不做 UI）
- 卡牌费用最低 0

## 参考分层

```text
BattleScreen（只读 BattleViewState + 发命令）
		│ BattleCommand
BattleClientSession ── ENet/UDP ── BattleServerSession
									  │
								  BattleEngine
```

已加入的基础代码：

- `scripts/net/battle_protocol.gd`：协议版本、消息类型、JSON 编解码
- `scripts/net/battle_server.gd`：ENet host、peer 连接/断开、消息收发
- `scripts/net/battle_client.gd`：ENet join/leave、HELLO/命令/服务器消息
- `BattleProtocol.DEFAULT_GAME_PORT = 45770`

当前服务器层只做传输边界；权威对局会话（按 peer 绑定阵营、命令校验、私有快照）是下一步。

- `BattleEngine` 仍是唯一权威状态；客户端不跑完整引擎（否则隐藏牌库无意义）
- 单机 vs AI 走内存版 ServerSession + 本地 ClientSession，复用同一套视图/命令接口
- 局域网 host = 本机 BattleServer + 回环 Client；host 玩家同样不能绕过服务器

## 命令

```json
{ "seq": 17, "turn": 3, "phase": "hand",
  "type": "play_card", "hand_index": 0,
  "target": { "column": 0, "slot": 1, "handles": [12, 15] } }
```

- 服务器校验后执行，返回 ack + 公共/私有事件；客户端在确认前锁定输入
- `handles` 用于多目标选择（最多 count 个）；锦囊多目标也使用同一字段
- 组队实体打向已有友方实体格时，服务器把原实体挪到同列另一空格，再把新实体放在目标格；这属于放置规则，不发位置变动事件
- `move_entity` 效果移动实体后发 `position_changed` 事件；移动牌的目标位置也用 `{column,slot}`，服务器需按被移动实体阵营和 `valid_move_slots` 校验
- 特殊回合命令：`{"type":"special_play","target":{...}}` / `{"type":"special_hand"}`
- 超能力牌池与当前 offer 只发给所属玩家；其他玩家只看到特殊回合状态
- 引擎统一入口：`BattleEngine.execute_command(side, command)`
- 超时自动 `end_phase`

## 私有/公开数据

| 数据 | 本人 | 对手 |
|---|---|---|
| 手牌内容（含有效攻击/费用） | 私有 | 不可见 |
| 手牌数量 | 可见 | 可见 |
| 牌库顺序/内容 | 不可见（只有数量） | 不可见 |
| 抽到的牌 | 私有 `card_drawn` | 只收到手牌数量变化 |
| 场上实体 | 公开 | 公开 |
| 特殊标志物 | 公开 | 公开 |
| 牌库/手牌被动的累计修正 | 私有（手牌可见时） | 不可见 |

## 四类特殊能力的同步

### 1. 入场选择最多两个其他友方实体 +2 攻击

伪代码：

```text
when enter:
	choose(2, "other_allies")
	buff_stats(chosen, 2, 0)
```

- 客户端选牌、可选 0~2 个其他友方实体，连同放置位置一起发 `play_card.handles`
- 服务器校验仍是合法 `other_allies`、数量 ≤2；原子地放置并执行入场
- 广播两个目标的攻击变化；动画事件 `ability` 的 `target_ids` 为被选目标
- 不足两个允许打出，效果作用于已选目标

### 2. 牌库内，每个友方死亡自身攻击 +1

伪代码：

```text
when ally_die(zone == 'deck'):
	gain_attack(1)
```

- 服务器维护牌库卡牌实例的 `attack_bonus`，不发给任何客户端
- 每次友方实体死亡，服务器遍历该玩家牌库实例，逐个累加
- 抽到该牌时发私有 `card_drawn`，带有效攻击力；本人此时才看到
- 加成跟随牌库→手牌保留，打出时转为实体攻击；对手只看到最终公开攻击力

### 3. 手牌内，每个友方死亡自身攻击 +1、费用 -1

伪代码：

```text
when ally_die(zone == 'hand'):
	gain_attack(1)
	reduce_cost(1)
```

- 服务器修改手牌实例修正，给本人发 `hand_card_updated`（instance_id、有效攻击/费用）
- 对手不可见
- 出牌时服务器按有效费用校验/扣费；客户端旧数据不一致时以服务器为准
- 费用最低 0；加成保留到打出并转为实体攻击

### 4. 特殊标志物条件

伪代码：

```text
when enter:
	if marker_count("special_marker_1") > 1:
		add_marker("special_marker_2", 3)
		add_marker("special_marker_3", -1)
```

- `BattlePlayerState.markers: Dictionary[String,int]`，名字任意英文字符串，数量允许负数
- 服务器执行条件与增减；标志物公开同步
- 事件示例：`markers_changed { side, changes }`；当前仅数据接口，不做 UI

## 角色/区域

- 牌库(deck)/手牌(hand) 的卡牌实例需要有独立身份（instance_id），否则同名多张无法分别累计
- 加成跟随实例移动；打出时：
  - 实体攻击 = 基础攻击 + 实例 attack_bonus
  - 费用 = max(基础费用 + 实例 cost_delta, 0)
- 隐藏区域被动的触发对对手不可见，不发动画事件；本人手牌更新可自行播手牌闪光

## 逐列战斗结算作为同步点（2026-11-28）

战斗阶段现在天然是"可分的"：引擎支持逐列推进（`combat_step_mode`），一列 = 攻击 → 死亡 → 双重打击 → 清列内战斗 Buff 的完整单元。

- 服务器侧：`advance_phase()` 进入 combat 后不再一次性算完；逐列调用
  `resolve_next_combat_column()`，每列发一条 `combat_column_resolved { turn, column, events }`，
  最后一列之后 `finish_combat_resolution()` 进入回合结束/下一回合。
- 客户端侧：收到某列事件 → 播该列动画 → 播完才允许展示下一列。这是**表现层节奏**，
  不是协议条件。
- **不要把"动画播完"当作网络同步条件**：动画时长取决于素材、帧率、是否缺失动画，
  两端不可能一致；一旦某个客户端卡顿或素材被改，另一方会被迫等待。
  协议只同步"第几列结算完了 + 事件批次"，动画各自播放。
- 需要"双方看起来同步"时的折中：客户端播完动画前不发下一条 `ack`（表现层 pacing），
  但服务器有超时（建议 1.5s/列，无头客户端 0s），超时直接推进并在下一条消息里补发。
- 断线重连的最小重放单元就是"列号 + 该列事件批次"；查询点建议按列，而不是按整轮。
- 已分胜负时不结算剩余列，服务器与客户端都必须按同一规则提前结束本阶段。

## 动画回调

服务端只发：

```json
{ "type": "animation", "trigger": "attack",
  "actor_id": 12, "target_ids": [7,9], "hit_index": 1, "hit_count": 2 }
```

- 客户端解析卡牌 `animation` 伪代码并播放；服务端不执行动画
- 同时攻击多个目标：一个事件、`target_ids` 数组，`target` 动画应用到全部
- 多段/依次攻击：每段独立事件，完整重播 `when attack`
- 法术：`trigger="cast"`，`target_ids` 为全部目标，无目标为空
- 全局特效：客户端解析 `play_fx(global, "名字")`，放到全局层
- 死亡目标视图已移除时用 ghost 视图播放

## 死亡结算顺序（服务器）

1. 标记死亡并广播死亡公开事件
2. 场上实体 `when die`/友方死亡效果
3. 该玩家牌库/手牌实例的 `ally_die(zone=...)` 被动
4. 对本人发私有手牌更新（牌库不通知）
5. 胜负/阶段推进

多个实体同时死亡按确定性顺序逐个处理；每个友方死亡给每个相关实例各加一次。
