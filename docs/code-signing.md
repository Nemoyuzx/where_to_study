# Windows / Linux 签名与构建来源验证

## 当前结论

| 分发物 | 已配置的信任机制 | 仍需外部条件 |
| --- | --- | --- |
| Windows NSIS | `v*` 标签构建使用 GitHub OIDC 生成 Sigstore/SLSA 构建来源证明，并在 CI 内回验 | Windows“已验证发布者”仍需公众信任的 Authenticode 证书或 Microsoft Artifact Signing Public Trust 配置 |
| Linux Debian / AppImage | `v*` 标签构建使用 GitHub OIDC 生成 Sigstore/SLSA 构建来源证明，并在 CI 内回验 | 当前 GitHub 直链分发没有可由系统安装器自动信任的统一 Linux 证书 |
| Linux CLI / TUI | 与图形客户端相同，对两个架构的最终 `tar.gz` 生成并回验来源证明 | 如需独立于 GitHub 的维护者身份，还要另行建立 OpenPGP 密钥发布和轮换制度 |

这些来源证明不使用仓库长期私钥。GitHub Actions 为每次标签工作流签发短期 OIDC 身份，`actions/attest` 把最终文件摘要、仓库、提交、引用和签名工作流写入可验证的证明。它证明制品来自指定构建链，不等同于保证代码没有漏洞，也不等同于 Windows Authenticode。

本配置只对合入后的新 `v*` 标签构建生效，不会追溯签署已经发布的 `v0.2.7` 文件。不得通过重新指向旧标签来补签；应使用新的版本标签构建新的最终字节。

## 下载后验证

安装 [GitHub CLI](https://cli.github.com/) 后，对下载文件执行与其构建工作流匹配的命令。例如：

```bash
# Windows NSIS（可在 Windows PowerShell、macOS 或 Linux 中验证来源证明）
gh attestation verify ./Where-To-Study-vX.Y.Z-windows-x64-setup.exe \
  --repo Nemoyuzx/where_to_study \
  --signer-workflow Nemoyuzx/where_to_study/.github/workflows/build-windows.yml \
  --source-ref refs/tags/vX.Y.Z \
  --deny-self-hosted-runners

# Linux 图形客户端
gh attestation verify ./Where-To-Study-vX.Y.Z-linux-x86_64.AppImage \
  --repo Nemoyuzx/where_to_study \
  --signer-workflow Nemoyuzx/where_to_study/.github/workflows/build-linux.yml \
  --source-ref refs/tags/vX.Y.Z \
  --deny-self-hosted-runners

# Linux CLI；TUI 将 build-cli.yml 改为 build-tui.yml
gh attestation verify ./where-to-study-cli-linux-x86_64.tar.gz \
  --repo Nemoyuzx/where_to_study \
  --signer-workflow Nemoyuzx/where_to_study/.github/workflows/build-cli.yml \
  --source-ref refs/tags/vX.Y.Z \
  --deny-self-hosted-runners
```

验证成功只接受以下身份边界：本仓库、对应的固定工作流、准确的发布标签，以及 GitHub 托管 runner。具体机制见 [GitHub Artifact Attestations](https://docs.github.com/en/actions/concepts/security/artifact-attestations)。

## Windows Authenticode 接入边界

Windows Explorer、UAC 和 SmartScreen 所显示的“已验证发布者”必须来自公众信任的 Authenticode 签名。自签名证书、GitHub attestation 和 SHA-256 文件都不能替代它。

优先方案是 Microsoft Artifact Signing（原 Trusted Signing）Public Trust：

1. 维护者本人在 Azure Portal 完成真实个人或组织身份验证，并创建 Public Trust certificate profile。该步骤涉及法律身份、支持地区和可能的费用，不能由 CI 或自动化代办。
2. 创建 Microsoft Entra 应用及 service principal；给它添加 GitHub Environment 对应的 federated credential。
3. 只在目标 certificate profile scope 授予 `Artifact Signing Certificate Profile Signer`，不授予订阅级 Owner/Contributor。
4. GitHub 使用受保护的 `windows-code-signing` Environment，并保存下列非私钥配置：

   - `AZURE_CLIENT_ID`
   - `AZURE_TENANT_ID`
   - `AZURE_SUBSCRIPTION_ID`
   - `AZURE_ARTIFACT_SIGNING_ENDPOINT`
   - `AZURE_ARTIFACT_SIGNING_ACCOUNT`
   - `AZURE_ARTIFACT_SIGNING_CERTIFICATE_PROFILE`

5. 标签 job 必须按顺序执行：`tauri build --no-bundle` → 签名主程序 EXE → `tauri bundle --bundles nsis` → 签名 NSIS installer → `signtool verify /pa /all /v /tw` → 生成 SHA-256 → 安装烟测 → provenance attestation。

官方入口：[Artifact Signing quickstart](https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart)、[GitHub Azure OIDC](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-azure)、[Artifact Signing GitHub Action](https://github.com/Azure/artifact-signing-action)。

如果申请主体不在 Artifact Signing Public Trust 支持地区，应选择能验证该主体的商业 CA 代码签名证书。新签发的 OV 私钥通常必须位于 CA 云 HSM 或硬件令牌，不能假定能导出 PFX。只有已经合法持有、CA 允许导出的 PFX 才采用临时导入方案；证书、密码和私钥不得提交到仓库，签名后必须从 runner 清除。具体接法取决于最终 CA 的 KSP/CSP、云签名 CLI 或硬件令牌，不能混用另一提供商的流程。

无论采用哪种方式，都必须使用 SHA-256 和 RFC 3161 时间戳，并同时验证原始主程序、最终安装器和静默安装后的主程序。有效 Authenticode 有助于建立发布者信誉，但不能承诺新证书首次发布就一定消除 SmartScreen 提示。

## Linux 的平台信任边界

Linux 没有覆盖 `.deb`、AppImage 和压缩包的统一公众代码签名证书：

- APT 原生验证的是签名的仓库 `InRelease` / `Release.gpg`，再沿 `Packages` 摘要验证 `.deb`。`apt install ./local.deb` 不会建立这条仓库信任链。
- AppImage 可以嵌入 OpenPGP 签名，但 AppImage runtime 不会默认强制验证，用户仍需外部验证工具和可信公钥。
- `dpkg-sig`、`debsigs` 或 detached `.asc` 都要求用户显式配置/执行验证，不会自动获得系统平台信任。

因此当前 GitHub Release 直链采用 keyless GitHub attestation。若以后需要 APT 原生体验，应单独建立 HTTPS APT repository、离线 archive signing key、`InRelease`、`Release.gpg` 和 `Signed-By` keyring；这是一套仓库分发基础设施，而不是给单个 `.deb` 加一个证书。参考 [Debian apt-secure(8)](https://manpages.debian.org/stable/apt/apt-secure.8.en.html) 与 [AppImage signing](https://docs.appimage.org/packaging-guide/optional/signatures.html)。

## English summary

New `v*` builds of the Windows installer and all Linux Release archives receive keyless GitHub/Sigstore build-provenance attestations. Verification is constrained to this repository, the exact workflow, the exact release tag, and GitHub-hosted runners. Existing `v0.2.7` assets are not retroactively attested.

This does **not** make Windows display a verified publisher. Windows still requires a publicly trusted Authenticode identity, preferably Microsoft Artifact Signing Public Trust with GitHub OIDC when the legal person or organization is eligible, or a commercial CA-backed cloud HSM/hardware token otherwise. No private key or certificate password belongs in the repository.

Linux has no single platform certificate for direct `.deb`, AppImage, and tarball downloads. GitHub attestations are the primary trust mechanism for the current distribution model. Native APT trust would require a separately operated repository with signed `InRelease` metadata and a pinned `Signed-By` keyring.
