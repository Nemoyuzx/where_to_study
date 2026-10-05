// One app-lifetime owner for course/assignment DTOs. Secrets and browser state
// never enter this store, localStorage or diagnostics.
const empty=()=>({courses:null,assignments:null,fetchedAt:'',cloudBusy:false,cloudError:'',cacheWarning:false,qm:null})
export class CourseDataOwner {
  constructor(command) {
    this.command=command;this.listeners=new Set();this.state=empty()
    this.cloudRevision=0;this.qmRevision=0;this.cloudKey=null;this.qmKey=null
    this.cloudEnabled=false;this.qmEnabled=false;this.live=true
    this.cloudFlight=null;this.hydration=null;this.qmFlight=null;this.qmRead=null
  }
  getSnapshot=()=>this.state
  subscribe=listener=>{this.listeners.add(listener);return()=>this.listeners.delete(listener)}
  publish(value){if(!this.live)return;this.state={...this.state,...value};for(const listener of this.listeners)listener()}
  configure({cloudKey,cloudEnabled,qmKey,qmEnabled}) {
    if(!this.live){this.live=true;this.cloudKey=null;this.qmKey=null}
    if(this.cloudKey!==cloudKey||this.cloudEnabled!==cloudEnabled) {
      this.cloudRevision++;this.cloudKey=cloudKey;this.cloudEnabled=cloudEnabled
      this.cloudFlight=null;this.hydration=null
      this.publish({courses:null,assignments:null,fetchedAt:'',cloudBusy:false,cloudError:'',cacheWarning:false})
      const revision=this.cloudRevision
      if(cloudEnabled)void this.hydrate().then(()=>{
        if(this.live&&this.cloudEnabled&&revision===this.cloudRevision)return this.refresh(true)
      }).catch(()=>{})
    }
    if(this.qmKey!==qmKey||this.qmEnabled!==qmEnabled) {
      this.qmRevision++;this.qmKey=qmKey;this.qmEnabled=qmEnabled;this.qmFlight=null;this.qmRead=null
      this.publish({qm:null})
      const revision=this.qmRevision
      if(qmEnabled)void this.reloadQM().then(()=>{
        if(this.live&&this.qmEnabled&&revision===this.qmRevision)return this.syncQM(true)
      }).catch(()=>{})
    }
  }
  acceptCloud(value,revision) {
    if(!this.live||!this.cloudEnabled||revision!==this.cloudRevision||!value||
      !Array.isArray(value.courses)||!Array.isArray(value.assignments))return
    this.publish({courses:value.courses,assignments:value.assignments,fetchedAt:value.fetched_at||'',
      cacheWarning:Boolean(value.cache_warning),cloudError:''})
  }
  hydrate() {
    if(!this.cloudEnabled)return Promise.resolve(null)
    if(this.hydration)return this.hydration
    const revision=this.cloudRevision
    const work=this.command('fetch_course_list',{catalogue:true,cache_only:true,force:false})
      .then(value=>{this.acceptCloud(value,revision);return value}).catch(()=>null)
    this.hydration=work
    return work
  }
  refresh(force=true) {
    if(!this.cloudEnabled)return Promise.reject(new Error('请先在设置中保存教务账号和密码。'))
    if(this.cloudFlight)return this.cloudFlight
    const revision=this.cloudRevision
    this.publish({cloudBusy:true,cloudError:''})
    const work=this.command('fetch_course_list',{catalogue:true,cache_only:false,force})
      .then(value=>{this.acceptCloud(value,revision);return value})
      .catch(error=>{if(this.live&&revision===this.cloudRevision)this.publish({cloudError:'课程获取失败。'});throw error})
      .finally(()=>{if(this.cloudFlight===work){this.cloudFlight=null;this.publish({cloudBusy:false})}})
    this.cloudFlight=work
    return work
  }
  async ensureCloud() {
    const revision=this.cloudRevision
    await this.hydrate()
    if(!this.live||!this.cloudEnabled||revision!==this.cloudRevision)throw new Error('账户已更改，请重新获取。')
    if(this.state.assignments!==null)return this.state
    await this.refresh(false)
    if(!this.live||!this.cloudEnabled||revision!==this.cloudRevision)throw new Error('账户已更改，请重新获取。')
    return this.state
  }
  async assignmentsForDates(start,end=start) {
    const revision=this.cloudRevision
    const value=await this.ensureCloud()
    if(!this.live||revision!==this.cloudRevision)throw new Error('账户已更改，请重新获取。')
    return {source:'https://ucloud.bupt.edu.cn/uclass/',items:(value.assignments||[]).filter(item=>{
      const date=String(item.deadline||'').slice(0,10)
      return date>=start&&date<=end
    })}
  }
  reloadQM() {
    if(!this.qmEnabled)return Promise.resolve(null)
    if(this.qmRead)return this.qmRead
    const revision=this.qmRevision
    const work=this.command('load_qmplus').then(value=>{
      if(this.live&&this.qmEnabled&&revision===this.qmRevision)this.publish({qm:value})
      return value
    }).finally(()=>{if(this.qmRead===work)this.qmRead=null})
    this.qmRead=work
    return work
  }
  syncQM(background=false) {
    if(!this.qmEnabled)return Promise.reject(new Error('QMplus 尚未启用。'))
    if(this.qmFlight&&background)return this.qmFlight
    // An explicit Connect may upgrade the current quiet native owner. Native
    // code owns the nonce/SSO budget; this store never supplies credentials.
    const work=this.command('connect_qmplus',background?{background:true}:undefined)
      .finally(()=>{if(this.qmFlight===work)this.qmFlight=null})
    this.qmFlight=work
    return work
  }
  resetCloud(){this.cloudRevision++;this.cloudFlight=null;this.hydration=null;this.publish({courses:null,assignments:null,fetchedAt:'',cloudBusy:false,cloudError:'',cacheWarning:false})}
  clear(){this.cloudEnabled=false;this.qmEnabled=false;this.resetCloud();this.qmRevision++;this.qmFlight=null;this.qmRead=null;this.publish({qm:null})}
  dispose(){this.clear();this.live=false;this.listeners.clear()}
}
