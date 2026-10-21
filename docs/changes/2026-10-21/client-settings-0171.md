# 客户端 0.17.1（39）：设置面板（点左上角头像）

## 改了什么
- 点左上角头像打开「设置」弹窗，**按已批设计稿** `q_design/q_settings_popup` + `q_settings_states`（SPEC_Q §17.4）还原：
  popup_frame 960×1314 + 绶带「设 置」+ 右上红色关闭 + 「点击空白处关闭」；新切图 19 张入库（toggle_switch_on/off、tile_setting(_off)、
  tag_unopened、btn_red_100/124、icon_set_*；九宫格边距写进 q_nine.gd，授权行追加到 art_q_license_list.csv）。
  - 账号：头像 + 名字 + 境界胶囊；「账号」（中间打码，手机号 3+4）/「服务器」两行（账号信息来自新接口 `GET /api/v1/me/account`，登录时也在本机记一份）。
  - 声音：音乐 / 音效开关，存在本机 `user://settings.cfg`，作用到音频总线 `Music` / `SFX`（没有就运行时建，接到 Master；以后的背景音乐 / 音效播放器把 bus 设成这两个即可受控）。
  - 声音开关用整张切图 toggle_switch_on/off。
  - 更多：修改密码 / 绑定手机 / 兑换码 / 客服反馈 / 用户协议与隐私政策（灰格 + 「未开放」角标，可点）→ 带锁 toast「功能暂未开放」（toast_bg_lock），弹窗不关。
  - 版本号「v0.17.1（39）」+「检查更新」（检查中按钮灰掉显示「检查中…」；已是最新 → 绿字 + toast；有新版本 → 收起设置走原来的更新弹窗；失败 toast 原因）。
  - 素材致谢：稿上没有入口，点版本号区域打开原来的致谢页（CC BY 署名要能看到；用户协议页开放后挪过去）。
  - 退出登录（红色大按钮）→ 二次确认（再压暗 + 小弹窗「确定要退出当前账号吗？」取消 / 退出） → 服务器作废令牌（`POST /auth/logout`，网络失败不拦着）+ 清本机令牌和账号记录 → 停心跳、清空上个账号的界面数据和背包「新」标记 → 回登录页，可登录别的账号。
- 删除：main.tscn 里旧的 SettingsPage（显示战斗记录 / 满包处理 / 音量 / 导出存档）和旧的 ⚙ SettingsButton；场景测试同步去掉这几个节点名。

## 服务器
- 新增只读 `GET /api/v1/me/account` → `{ playerId, username }`（玩家鉴权）。无迁移。

## 测试
- GUT `tests/unit/test_settings.gd`：退出登录清令牌 / 账号、回登录页、旧账号数据清空、可再登录；音乐 / 音效开关写盘并静音总线；暂未开放提示；旧设置项不再出现。全量 GUT 通过。
- 后端 `auth/routes.test.ts` 覆盖 `/me/account`（登录后 200、未登录 / 退出后 401）。
