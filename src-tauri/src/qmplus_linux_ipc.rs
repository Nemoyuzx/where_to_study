//! Preserve full-document capability checks for Linux QMplus authentication.
//! Installed through the supported Tauri hook before app.build(); only the
//! QMplus window selects native IPC. Other windows retain the stock transport.
//!
//! Tauri's stock fetch transport identifies the caller using its Origin header,
//! whereas Wry's native bridge supplies the full current document URI to the same
//! Tauri invoke-key and capability checks. Only the Linux QMplus view selects that
//! existing native transport. No custom command handler or new permission exists.

/// Install the window-scoped transport choice at Tauri's initialization hook.
pub fn configure<R: tauri::Runtime>(builder: tauri::Builder<R>) -> tauri::Builder<R> {
    #[cfg(target_os = "linux")]
    {
        builder.invoke_system(initialization_script())
    }
    #[cfg(not(target_os = "linux"))]
    {
        builder
    }
}

#[cfg(target_os = "linux")]
fn initialization_script() -> String {
    // These templates are private inside Tauri; there is no public getter for
    // Builder's rendered default script. Keep the pinned upstream copies below
    // byte-identical and select the existing native fallback at send time.
    STOCK_IPC_SCRIPT
        .replace("__TEMPLATE_invoke_key__", "__INVOKE_KEY__")
        .replace("__RAW_process_ipc_message_fn__", STOCK_PROCESS_IPC_MESSAGE)
        .replace("__TEMPLATE_os_name__", "\"linux\"")
        .replace(
            "__TEMPLATE_fetch_channel_data_command__",
            "\"plugin:__TAURI_CHANNEL__|fetch\"",
        )
        .replace("function sendIpcMessage(message) {", QMPLUS_DISPATCH)
}

// Reuse the stock native fallback, including its envelope and serializer.
// Metadata is read when sending: Tauri installs it after this initialization.
// Both labels must match; missing metadata uses the untouched stock sender.
// customProtocolIpcBlocked also keeps binary replies on Tauri's native reply path.
#[cfg(target_os = "linux")]
const QMPLUS_DISPATCH: &str = r#"function sendIpcMessage(message) {
    const metadata = window.__TAURI_INTERNALS__.metadata
    if (
      osName === 'linux'
      && metadata?.currentWindow?.label === 'qmplus'
      && metadata?.currentWebview?.label === 'qmplus'
    ) {
      customProtocolIpcFailed = true
    }"#;

// Unmodified Tauri 2.12.1 source:
// https://github.com/tauri-apps/tauri/blob/tauri-v2.12.1/crates/tauri/scripts/ipc-protocol.js
// Copyright and dual Apache-2.0/MIT SPDX notices are retained in each copy.
// Update these copies and the byte pins together when changing Tauri versions.
#[cfg(target_os = "linux")]
const STOCK_IPC_SCRIPT: &str = r#"// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

;(function () {
  /**
   * A runtime generated key to ensure an IPC call comes from an initialized frame.
   *
   * This is declared outside the `window.__TAURI_INVOKE__` definition to prevent
   * the key from being leaked by `window.__TAURI_INVOKE__.toString()`.
   */
  const __TAURI_INVOKE_KEY__ = __TEMPLATE_invoke_key__

  const processIpcMessage = __RAW_process_ipc_message_fn__
  const osName = __TEMPLATE_os_name__
  const fetchChannelDataCommand = __TEMPLATE_fetch_channel_data_command__
  let customProtocolIpcFailed = false

  // on Android we never use it because Android does not have support to reading the request body
  const canUseCustomProtocol = osName !== 'android'

  function sendIpcMessage(message) {
    const { cmd, callback, error, payload, options } = message

    if (
      !customProtocolIpcFailed
      && (canUseCustomProtocol || cmd === fetchChannelDataCommand)
    ) {
      const { contentType, data } = processIpcMessage(payload)

      const headers = new Headers((options && options.headers) || {})
      headers.set('Content-Type', contentType)
      headers.set('Tauri-Callback', callback)
      headers.set('Tauri-Error', error)
      headers.set('Tauri-Invoke-Key', __TAURI_INVOKE_KEY__)

      fetch(window.__TAURI_INTERNALS__.convertFileSrc(cmd, 'ipc'), {
        method: 'POST',
        body: data,
        headers
      })
        .then((response) => {
          const callbackId =
            response.headers.get('Tauri-Response') === 'ok' ? callback : error
          // we need to split here because on Android the content-type gets duplicated
          switch ((response.headers.get('content-type') || '').split(',')[0]) {
            case 'application/json':
              return response.json().then((r) => [callbackId, r])
            case 'text/plain':
              return response.text().then((r) => [callbackId, r])
            default:
              return response.arrayBuffer().then((r) => [callbackId, r])
          }
        })
        .then(
          ([callbackId, data]) => {
            window.__TAURI_INTERNALS__.runCallback(callbackId, data)
          },
          (e) => {
            console.warn(
              'IPC custom protocol failed, Tauri will now use the postMessage interface instead',
              e
            )
            // failed to use the custom protocol IPC (either the webview blocked a custom protocol or it was a CSP error)
            // so we need to fallback to the postMessage interface
            customProtocolIpcFailed = true
            sendIpcMessage(message)
          }
        )
    } else {
      // otherwise use the postMessage interface
      const { data } = processIpcMessage({
        cmd,
        callback,
        error,
        options: {
          ...options,
          customProtocolIpcBlocked: customProtocolIpcFailed
        },
        payload,
        __TAURI_INVOKE_KEY__
      })
      // `window.ipc.postMessage` came from `tauri-runtime-wry` > `wry` [`with_ipc_handler`](https://github.com/tauri-apps/wry/blob/a0403b9e2f1ff9d73be7dce1184f058afcaa1d82/src/lib.rs#L1130)
      window.ipc.postMessage(data)
    }
  }

  Object.defineProperty(window.__TAURI_INTERNALS__, 'postMessage', {
    value: sendIpcMessage
  })
})()
"#;

// https://github.com/tauri-apps/tauri/blob/tauri-v2.12.1/crates/tauri/scripts/process-ipc-message-fn.js
#[cfg(target_os = "linux")]
const STOCK_PROCESS_IPC_MESSAGE: &str = r#"// Copyright 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

// this is a function and not an iife so use it carefully

(function (message) {
  if (
    message instanceof ArrayBuffer
    || ArrayBuffer.isView(message)
    || Array.isArray(message)
  ) {
    return {
      contentType: 'application/octet-stream',
      data: message
    }
  } else {
    const data = JSON.stringify(message, (_k, val) => {
      // if this value changes, make sure to update it in:
      // 1. ipc.js
      // 2. core.ts
      const SERIALIZE_TO_IPC_FN = '__TAURI_TO_IPC_KEY__'

      if (val instanceof Map) {
        return Object.fromEntries(val.entries())
      } else if (val instanceof Uint8Array) {
        return Array.from(val)
      } else if (val instanceof ArrayBuffer) {
        return Array.from(new Uint8Array(val))
      } else if (
        typeof val === 'object'
        && val !== null
        && SERIALIZE_TO_IPC_FN in val
      ) {
        return val[SERIALIZE_TO_IPC_FN]()
      } else {
        return val
      }
    })

    return {
      contentType: 'application/json',
      data
    }
  }
})
"#;
