---
name: implement-backend
description: Use when adding or changing backend APIs, settlement, content publish, operation logs, or data repairs.
---

# 实现后端

1. 新业务放在自己的一块里。结算、突破、战力是纯规则，测试时不启动网站。
2. 接口只接收请求、调用规则、写入数据库。修数据的程序不写进结算接口。
3. 会改进度或配置的操作，补上操作记录的测试：成功有前后数值，失败有原因且进度不变。
4. 修复程序补三个测试：预览不写数据，确认后写入，再执行一次不会改第二次。
5. 玩家会话调用管理接口的测试必须失败。
