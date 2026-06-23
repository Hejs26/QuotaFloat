# QuotaFloat 隐私说明

QuotaFloat 是本地运行的开源 macOS 工具，不包含账号系统、广告、遥测或用户行为统计。

## 凭证如何读取

- **Codex**：读取 `CODEX_HOME/auth.json` 中由 Codex Desktop、CLI 或 IDE 扩展共享的本机登录
  缓存；未设置 `CODEX_HOME` 时默认读取 `~/.codex/auth.json`。
- **Claude**：优先调用 macOS 自带的 `/usr/bin/security`，读取 Claude Code 已保存的 OAuth
  access token 和权限范围。凭证只在当前进程内存中用于请求 Anthropic 官方额度接口。QuotaFloat
  不启用容易反复弹窗的 Keychain API 读取方式，但 macOS 仍可能根据钥匙串状态要求系统授权。
- **Kimi**：由用户在 QuotaFloat 中手动输入 Coding Plan API Key。密钥保存在
  `~/Library/Application Support/QuotaFloat/kimi-code-api-key`，文件权限设置为 `600`。

QuotaFloat 不会把 Codex、Claude 或 Kimi 凭证写入项目目录，也不会在正常日志中输出凭证内容。

## 网络请求

额度刷新只会连接所选服务对应的官方接口。QuotaFloat 不会把凭证、额度数据或使用信息上传给
QuotaFloat 作者、分析平台、广告服务或其他非必要第三方。

## 本地数据

最后一次成功获取的额度会缓存在：

`~/Library/Application Support/QuotaFloat/quota-cache.json`

缓存用于断网或接口失败时继续显示旧数据。用户可以退出 QuotaFloat 后自行删除该文件。

## 上游依赖

QuotaFloat 内置开源的 `CodexBarCore` 取数能力。上游许可证保存在
`ThirdPartyLicenses/CodexBar-LICENSE.txt`。
