import {useEffect, useRef, useState, useId} from 'react'
import {ExternalLink, KeyRound, Trash2, ChevronDown} from 'lucide-react'
import {uiText} from './ui-text.js'
import {listen} from '@tauri-apps/api/event'

// Secret drafts never enter App settings, localStorage, URL, diagnostics or cache.
export default function QmplusLoginSettings({language, command, native, enabled = false, onEnabledChange, featureBusy = false}) {
  const text = (key, english) => uiText(language, key, english)
  const [account, setAccount] = useState('')
  const [password, setPassword] = useState('')
  const [status, setStatus] = useState({saved:false, enabled:false})
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [connection, setConnection] = useState({phase:'',reason:''})
  const [expanded,setExpanded]=useState(enabled)
  const bodyID=useId()
  const owner = useRef(0)
  useEffect(()=>{setExpanded(enabled)},[enabled])
  useEffect(() => {
    const generation = ++owner.current
    if(native) command('load_qmplus_login').then(value=>{
      if(owner.current===generation)setStatus(value)
    }).catch(()=>{if(owner.current===generation)setError('无法读取 QMplus 安全存储。')})
    let release
    if(native) {
      command('load_qmplus_connection_status').then(value=>{if(owner.current===generation)setConnection(value)}).catch(()=>{})
      listen('qmplus:connection-status',event=>{if(owner.current===generation)setConnection(event.payload)})
        .then(unlisten=>{if(owner.current===generation)release=unlisten;else unlisten()}).catch(()=>{})
    }
    return()=>{owner.current++;release?.()}
    // Locale updates keep this editor and its transaction alive.
  }, [command,native])
  async function perform(name, args) {
    if(busy||!native)return
    const generation=owner.current
    setBusy(true);setError('')
    try {
      const value=await command(name,args)
      if(owner.current===generation)setStatus(value)
    } catch (failure) {
      // These native commands expose only fixed, non-sensitive error strings.
      const fixedError=typeof failure==='string'?failure:failure?.message
      if(owner.current===generation)setError(typeof fixedError==='string'&&fixedError.length<=180
        ? fixedError
        : 'QMplus 安全设置未能保存，请重试。')
      // A cleanup barrier may have saved/removed vault data without authorizing
      // a new web identity. Read the fixed status instead of keeping stale UI.
      try {
        const value=await command('load_qmplus_login')
        if(owner.current===generation)setStatus(value)
      }catch{}
    } finally {
      if(owner.current===generation){setBusy(false);setAccount('');setPassword('')}
    }
  }
  // Only app-owned phases select static localized UI text. Fixed QA reason
  // metadata is never shown as a user-facing message or passed to a translator.
  const connectionText = (() => {
    if(connection.phase==='synced')return text('QMplus 同步完成','QMplus sync completed')
    if(connection.phase==='partial')return text('QMplus 同步不完整，部分信息尚未获取，请重试','QMplus sync is incomplete. Some information is still unavailable; try again.')
    if(connection.phase==='failed')return text('QMplus 同步失败，请检查官方网页登录状态后重试','QMplus sync failed. Check your official webpage sign-in and try again.')
    if(connection.phase==='cancelled')return text('QMplus 同步已取消，可重新连接后重试','QMplus sync was cancelled. Reconnect to try again.')
    if(connection.phase==='submitted'&&connection.reason==='USERNAME_SUBMITTED')return text('账号已提交到官方页面；如出现其他验证，请手动完成。','The account was submitted to the official page. Complete any further checks manually.')
    if(connection.phase==='submitted'&&connection.reason==='PASSWORD_SUBMITTED')return text('密码已提交到官方页面；MFA 与其他确认请由您手动完成。','The password was submitted to the official page. Complete MFA and other confirmations manually.')
    if(connection.phase==='manual')return text('请在官方网页完成登录、验证码或 MFA。应用不会替你确认风险、同意协议或绕过验证。','Complete sign-in, CAPTCHA or MFA on the official page. The app never accepts risks or agreements or bypasses verification for you.')
    if(['checking','username','password'].includes(connection.phase))return text('正在确认 QMplus 登录状态…','Checking QMplus sign-in status…')
    return ''
  })()
  return <section className="panel">
    <div className="panel-title qmplus-title"><KeyRound size={18}/><h2>QMplus</h2><small>{text('仅适用国院','For the International School only')}</small>
      <button type="button" className="qmplus-settings-disclosure" aria-label="QMplus" aria-expanded={expanded} aria-controls={bodyID} onClick={()=>setExpanded(value=>!value)}><ChevronDown size={18} aria-hidden="true"/></button></div>
    <div className="settings-switch-row"><div><strong>{text('启用 QMplus','Enable QMplus')}</strong></div>
      <button type="button" className="settings-switch" role="switch" aria-checked={enabled}
        aria-label={text('启用 QMplus','Enable QMplus')} disabled={!native || featureBusy}
        onClick={()=>onEnabledChange?.(!enabled)}><span/></button></div>
    <div id={bodyID} className={`weather-strip-reveal ${expanded?'expanded':''}`} aria-hidden={!expanded} inert={!expanded}>
    <div className="weather-strip-reveal-clip"><div className="qmplus-settings-body">
    <p>{text('QMplus 使用独立的官方网页登录，与北邮教务账号无关。','QMplus uses a separate official web sign-in, independent of the academic account.')}</p>
    <p>{text('关闭“启用 QMplus”只暂停连接和同步，保留登录资料、会话及课程缓存。关闭自动填写、删除登录资料或退出并清除数据，请使用对应操作。','Turning off “Enable QMplus” only pauses connection and sync; saved credentials, the session and course cache are retained. Use the separate controls to turn off autofill, delete credentials, or disconnect and clear data.')}</p>
    <p>{text('可选：在本机安全存储中保存独立 QMplus 账号和密码。默认关闭自动填写；验证码、MFA 和其它验证仍需你在官方窗口完成。','Optional: save separate QMplus credentials in secure storage on this device. Autofill is off by default; CAPTCHA, MFA and other verification still require the official window.')}</p>
    <p>{text('仅在已核验的官方登录页自动选择精确匹配的已保存账号，并填写账号和密码，各步骤最多一次。未匹配的账号选择、MFA、验证码、保持登录、风险及协议确认仍须本人操作。','Only verified official sign-in pages may select the exact saved account and fill the username and password, with each step attempted at most once. Unmatched account choices, MFA, CAPTCHA, staying signed in, risk and terms confirmations still require your action.')}</p>
    <label>{text('QMplus 邮箱','QMplus email')}
      <input type="email" autoComplete="off" spellCheck={false} value={account} disabled={busy||!native}
        onChange={event=>setAccount(event.target.value)} maxLength={320}/></label>
    <label>{text('QMplus 密码','QMplus password')}
      <input type="password" autoComplete="new-password" value={password} disabled={busy||!native}
        onChange={event=>setPassword(event.target.value)} maxLength={2048}/></label>
    <div className="query-action-row">
      <button type="button" disabled={busy||!native||!account.trim()||!password} onClick={()=>perform('save_qmplus_login',{account,password})}>
        <KeyRound size={16}/>{text('安全保存 QMplus 登录资料','Save QMplus credentials securely')}</button>
      <button type="button" disabled={busy||!native||!status.saved} onClick={()=>perform('clear_qmplus_login')}>
        <Trash2 size={16}/>{text('删除 QMplus 登录资料','Delete QMplus credentials')}</button>
    </div>
    <div className="settings-switch-row"><div><strong>{text('自动填写 QMplus 登录资料','Autofill QMplus credentials')}</strong>
      <span>{text('只在已核验的官方账号与密码表单填写，不会自动处理额外验证。','Only fills verified official account and password forms. Additional verification is never handled automatically.')}</span></div>
      <button type="button" className="settings-switch" role="switch" aria-checked={status.enabled}
        aria-label={text('自动填写 QMplus 登录资料','Autofill QMplus credentials')} disabled={busy||!native||!status.saved}
        onClick={()=>perform('set_qmplus_autofill',{enabled:!status.enabled})}><span/></button></div>
    <div className="query-action-row"><button type="button" disabled={!native||busy||!enabled||featureBusy} onClick={()=>command('connect_qmplus').catch(()=>setError('无法打开 QMplus。'))}>
      <ExternalLink size={16}/>{text('连接／同步 QMplus','Connect / sync QMplus')}</button>
      <button type="button" disabled={!native||busy} onClick={()=>perform('clear_qmplus_login')}>
        {text('退出并清除 QMplus 数据','Disconnect and clear QMplus data')}</button></div>
    {!native&&<small>{text('请使用原生客户端的官方 QMplus 登录窗口。','Use the official QMplus sign-in window in a native client.')}</small>}
    </div></div></div>
    {status.saved&&<small>{text('QMplus 登录资料已安全保存','QMplus credentials are securely saved')}</small>}
    {error&&<p role="alert">{text(error,'Unable to save QMplus security settings. Please retry.')}</p>}
    {connectionText&&<small role="status">{connectionText}</small>}
  </section>
}
