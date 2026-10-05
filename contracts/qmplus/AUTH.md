# QMplus 官方网页登录辅助契约（0.4.0 源码）

`qmplus-auth.js` 与只读业务同步脚本 `qmplus-sync.js` 完全分开。native 仅在用户已明确保存独立 QMplus/Microsoft 账号密码、开启匹配的本机授权，且当前 ArkWeb/WKWebView/WebView 是官方**主文档**时安装此脚本。安装必须返回固定 `AUTH_INSTALLED`；已有同名全局返回 `AUTH_CONFLICT`，不得向它发送凭据。脚本不发送网络请求、不读 Cookie/Storage，不注册可被网页主动调用的 native 密码桥。

`qmplus-page.js` 是独立的只读主文档分类器，只返回 `loading / guest / authenticated / error / unknown`，不创建消息桥、不读取输入、存储或会话键。只有经过当前 owner／文档的已登录证明，原生同步入口才可用。明确的 Moodle fatal-error 标记或异常对话框优先于菜单；普通课程提醒不是 fatal-error。手机首页可能没有 `notloggedin` class，仅当 `page-site-index`、无菜单和安全的同源 SAML 链接共同存在时才补判访客。共享同步脚本在读取会话键和每个业务请求之前重复验证，HTTP 200 的错误／欢迎详情不能误标为已获取。

重连从固定 Dashboard 发起新的 GET 并重新证明状态，不重用旧 DOM 作为有效会话证明。官方登录入口仅接受精确站点／允许路径和已核验链接，重复页首／页尾链接指向同一安全目的地不构成多个身份。登录回跳 POST 保留原请求与 WebKit 配置；网页自行关闭不代表认证完成，不可因此打断父窗口的原始回跳。不自动重放验证码、密码或 SAML ACS POST，也不自动删除账号或 Cookie 来恢复错误。

已核实的页面白名单仅包括 `https://qmplus.qmul.ac.uk` 的已登录用户菜单，以及 `https://login.microsoftonline.com/569df091-b013-40e3-86ee-bd9cb9e25814/saml2` 或同租户 `/login`。Microsoft 表单须唯一为 `form#i0281`，提交目标仍是同源同租户 `/login`；账号是可见 `input#i0116[name=loginfmt][type=email]`，普通下一步是可见 `input#idSIButton9[type=submit]`。密码阶段账号框已移除，可见 `input#i0118[name=passwd][type=password]`，`#displayName` 仅在网页内部与本机授权账号比对。预加载的 10×13、透明度 0 密码框**不是**可填写密码页。其它域名、路径、frame、未匹配的账号选择、MFA、验证码、风险、条款、Stay signed in 或未知表单均由用户手动处理。

1. native 为每次真实 document 生成非敏感 nonce，并维护 presentation/document epoch、每阶段一次提交的本机 ledger。helper 在本次 document 内还绑定首次检查时的完整地址，地址变化即拒绝，地址本身永不返回。页面调用 `WTSQmAuth.inspect(nonce, accountHint?)`，只接收固定 `{v:1,stage,document,accountMatch,reason}`；不会收到网址、账号、输入值、HTML 或令牌。
2. 仅当状态是明确的 `username`，才允许 `fillAndSubmit({document,stage:'username',account})`。不能同时传密码；辅助脚本在点击普通 Next 前再次校验官方主文档、nonce、表单、可见且无遮挡的唯一控件。
3. 已核验的账号选择页须有唯一 `#tilesHolder`；只接受可见 `div.table[role=button][data-test-id]` 中唯一、精确匹配已授权完整账号的条目。其唯一 `.table-cell.text-left.content` 和 `data-test-id` 必须同时匹配，点击命中必须属于该条目而非溢出菜单。重复、遮挡、禁用、其它输入框或验证控件均拒绝。`account` 阶段调用只携带账号和 nonce，不携带密码；点击前先消耗本机尝试额度，`ACCOUNT_SELECTED` ACK 单独记录，不伪装为账号输入提交成功。
4. 密码只在同一 document 内本 helper 已提交或已选择匹配账号、官方 `#displayName` 与所存账号精确匹配，且 native ledger、当前安全授权版本与 owner 也许可时，调用 `fillAndSubmit({document,stage:'password',account,password})`。它再次校验并最多点击一次普通 Sign in；任何失败均固定码、**不自动重试**。账号选择和输入各自最多一次，凭据提交后不再自动选择账号。如果账号步骤跨文档或官方页面改版，用户手动继续。

两方法只返回固定状态/原因码；密码只作为本次官方页填写调用的入参，不进入 inspect 结果、业务快照、日志、剪贴板、截图、Widget 或第三方服务。应用关闭自动填写/退出/清本地数据时撤销本机授权并清除独立安全存储；操作系统自己的密码管理器由用户另行控制。三端接线前须保持同一 canonical 脚本字节，按各端实际页面生命周期逐项验收；假 DOM 测试不能冒充真实 Microsoft MFA 成功。

Test: `node --test test/qmplus-auth.test.js`。

首次布局允许有限等待，但不放宽 URL、表单或提交次数。实际 Microsoft 页面会用同一 `placeholderContainer` 内的 `placeholderInnerContainer > .placeholder[aria-hidden=true]` 覆盖空输入框；只把这一已核验的提示结构视作该字段的点击区域，并再次验证文档、控件身份、可编辑性、尺寸及其它确认控件。任意其它遮罩、隐藏预加载密码框或未知控件仍拒绝自动填写。静默网页若因系统隐藏窗口而无法完成布局，可能需要显示原窗口后继续；不保证所有系统／登录分支完全静默。

Tauri 的本机提交 ledger 属于一次连接展示，跨导航保留账号选择／输入／密码阶段的已尝试记录；每个文档仅更换 nonce 与地址。密码必须获得同文档账号选择或提交成功的独立 ACK，且安全存储授权版本仍匹配。隐藏窗布局最多先等待 8 次，显示原窗后最多再等 8 次；静默流程总计最多 25 秒。超时、明确手动步骤、授权撤销、应用后台或关闭窗口会停止自动填写并清理轮询计时器。窗口之间切换不视为应用后台；macOS 还核对应用激活状态，以保留 Inspector 和系统对话框。此取消不删除已验证业务快照，也不关闭供用户完成 MFA 的官方页面。默认连接在已验证身份开始只读同步时自动收起，保留本次 owner 和请求，结果发布后自动返回；用户明确打开的官方课程或活动页仍保留。

“启用 QMplus”是功能开关，和“关闭自动填写并删除登录信息”不同。关闭功能只撤销当前 owner、停止后续同步、隐藏课程区域；保留独立安全记录、授权、会话和上次快照。关闭期间及重新启用后的旧回调均不能重新发布。新用户默认关闭，既有授权元数据可迁移为开启，明确的关闭记录优先；不读密码来决定默认值。
