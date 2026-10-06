// One app-lifetime owner for course/assignment DTOs. Secrets and browser state
// never enter this store, localStorage or diagnostics.
import {AssignmentSeen} from './assignment-seen.js'
import {isEbuCourse,isQmplusAssessmentActivity} from './course-domain.js'
const noticeSources=['ucloud','qmplus']
const newSummary=()=>({count:0,preview:[],latest:null,consumed:null})
// Native publications have a validated RFC3339 fetched_at. Retain nanoseconds
// so two genuine cloud fetches within one millisecond remain distinct.
function publicationStamp(value) {
  if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.[0-9]{1,9})?(?:Z|[+-]\d{2}:\d{2})$/.test(value))return null
  const match=value.match(/\.([0-9]{1,9})(?:Z|[+-]\d{2}:\d{2})$/)
  const fraction=match?.[1]||''
  const milliseconds=Date.parse(value)
  if(!Number.isFinite(milliseconds))return null
  const seconds=milliseconds-Number(fraction.padEnd(3,'0').slice(0,3))
  return BigInt(seconds)*1000000n+BigInt(fraction.padEnd(9,'0'))
}
const empty=()=>({courses:null,assignments:null,fetchedAt:'',cloudBusy:false,cloudError:'',cacheWarning:false,qm:null,newAssignments:[],newAssignmentCount:0,newAssignmentCounts:{ucloud:0,qmplus:0}})
export class CourseDataOwner {
  constructor(command,{nativeNotices=false}={}) {
    this.command=command;this.listeners=new Set();this.state=empty()
    this.cloudRevision=0;this.qmRevision=0;this.cloudKey=null;this.qmKey=null
    this.cloudEnabled=false;this.qmEnabled=false;this.live=true
    this.cloudFlight=null;this.hydration=null;this.qmFlight=null;this.qmRead=null
    this.notified=new Set()
    this.nativeNotices=nativeNotices
    this.noticeSummaries={ucloud:newSummary(),qmplus:newSummary()};this.noticeOrder=0
    this.browserSeen=new AssignmentSeen();this.term='';this.qmRestored=false
    this.qmReadAgain=false
  }
  getSnapshot=()=>this.state
  subscribe=listener=>{this.listeners.add(listener);return()=>this.listeners.delete(listener)}
  publish(value){if(!this.live)return;this.state={...this.state,...value};for(const listener of this.listeners)listener()}
  configure({cloudKey,cloudEnabled,qmKey,qmEnabled,term=''}) {
    if(this.term!==term){this.notified.clear();this.dismissNewAssignments()}
    this.term=term
    if(!this.live){this.live=true;this.cloudKey=null;this.qmKey=null}
    if(this.cloudKey!==cloudKey||this.cloudEnabled!==cloudEnabled) {
      this.resetNoticeSource('ucloud')
      this.cloudRevision++;this.cloudKey=cloudKey;this.cloudEnabled=cloudEnabled
      this.cloudFlight=null;this.hydration=null
      this.publish({courses:null,assignments:null,fetchedAt:'',cloudBusy:false,cloudError:'',cacheWarning:false})
      const revision=this.cloudRevision
      if(cloudEnabled)void this.hydrate().then(()=>{
        if(this.live&&this.cloudEnabled&&revision===this.cloudRevision)return this.refresh(true)
      }).catch(()=>{})
    }
    if(this.qmKey!==qmKey||this.qmEnabled!==qmEnabled) {
      this.resetNoticeSource('qmplus')
      this.qmRevision++;this.qmKey=qmKey;this.qmEnabled=qmEnabled;this.qmFlight=null;this.qmRead=null
      this.qmRestored=false
      this.qmReadAgain=false
      this.publish({qm:null})
      const revision=this.qmRevision
      if(qmEnabled)void this.reloadQM().then(()=>{
        if(this.live&&this.qmEnabled&&revision===this.qmRevision)return this.syncQM(true)
      }).catch(()=>{})
    }
  }
  acceptCloud(value,revision,restore=false) {
    if(!this.live||!this.cloudEnabled||revision!==this.cloudRevision||!value||
      !Array.isArray(value.courses)||!Array.isArray(value.assignments))return
    this.acceptNewAssignments('ucloud',value,restore)
    this.publish({courses:value.courses,assignments:value.assignments,fetchedAt:value.fetched_at||'',
      cacheWarning:Boolean(value.cache_warning),cloudError:''})
  }
  acceptNewAssignments(source,value,restore=false) {
    if(!noticeSources.includes(source)||!value||value.partial||!Array.isArray(value.courses))return
    const items=source==='ucloud'?value?.assignments:value?.activities
    if(!Array.isArray(items))return
    const eligible=(items||[]).filter(item=>source==='ucloud'||(['assignment','quiz'].includes(item.kind)&&isQmplusAssessmentActivity(item)&&value.courses?.some(course=>course.id===item.course_id&&course.current_term_status==='current'&&isEbuCourse(course))))
    const identity=item=>source==='ucloud'?item.id:`${item.course_id}:${item.kind}:${item.id}`
    const summary=this.noticeSummaries[source]
    const native=this.nativeNotices||Array.isArray(value.new_assignment_ids)
    const stamp=native?publicationStamp(value.fetched_at):null
    // A retired cached DTO must never regrow the current replay-key set. Clock
    // regressions fail closed for notices; the course DTO remains displayable.
    if(native&&(stamp===null||(summary.latest!==null&&stamp<summary.latest)))return
    if(native)summary.latest=stamp
    const current=new Set(eligible.map(item=>`${source}:${identity(item)}`))
    for(const key of this.notified)if(key.startsWith(`${source}:`)&&!current.has(key))this.notified.delete(key)
    const ids=new Set(native?(value.new_assignment_ids||[]):this.browserSeen.observe(source,String(source==='ucloud'?this.cloudKey:this.qmKey),this.term,eligible.map(identity),{restore}))
    if(native) {
      if(summary.consumed===stamp)return
      if(ids.size)summary.consumed=stamp
    }
    if(restore)return
    let count=0
    for(const item of eligible) {
      const id=identity(item)
      const key=`${source}:${id}`
      if(!ids.has(id)||this.notified.has(key))continue
      this.notified.add(key)
      count++
      if(summary.preview.length<8) {
        const course=value.courses?.find(course=>course.id===item.course_id)
        summary.preview.push({order:this.noticeOrder++,item:{...item,source,course_name:item.course_name||course?.name||'',deadline:item.deadline||item.due_at||item.closes_at||''}})
      }
    }
    if(count){summary.count+=count;this.publishNotices()}
  }
  publishNotices() {
    const newAssignmentCounts=Object.fromEntries(noticeSources.map(source=>[source,this.noticeSummaries[source].count]))
    const newAssignmentCount=newAssignmentCounts.ucloud+newAssignmentCounts.qmplus
    const newAssignments=noticeSources.flatMap(source=>this.noticeSummaries[source].preview).sort((a,b)=>a.order-b.order).slice(0,8).map(value=>value.item)
    if(!newAssignmentCount)this.noticeOrder=0
    this.publish({newAssignments,newAssignmentCounts,newAssignmentCount})
  }
  resetNoticeSource(source) {
    this.noticeSummaries[source]=newSummary()
    for(const key of this.notified)if(key.startsWith(`${source}:`))this.notified.delete(key)
    this.publishNotices()
  }
  dismissNewAssignments(){for(const source of noticeSources){this.noticeSummaries[source].count=0;this.noticeSummaries[source].preview=[]}this.publishNotices()}
  hydrate() {
    if(!this.cloudEnabled)return Promise.resolve(null)
    if(this.hydration)return this.hydration
    const revision=this.cloudRevision
    const work=this.command('fetch_course_list',{catalogue:true,cache_only:true,force:false})
      .then(value=>{this.acceptCloud(value,revision,true);return value}).catch(()=>null)
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
  async ensureCloud({force=false}={}) {
    const revision=this.cloudRevision
    if(this.state.assignments===null)await this.hydrate()
    if(!this.live||!this.cloudEnabled||revision!==this.cloudRevision)throw new Error('账户已更改，请重新获取。')
    if(!force&&this.state.assignments!==null)return this.state
    await this.refresh(force)
    if(!this.live||!this.cloudEnabled||revision!==this.cloudRevision)throw new Error('账户已更改，请重新获取。')
    return this.state
  }
  async assignmentsForDates(start,end=start,options={}) {
    const revision=this.cloudRevision
    const value=await this.ensureCloud(options)
    if(!this.live||revision!==this.cloudRevision)throw new Error('账户已更改，请重新获取。')
    return {source:'https://ucloud.bupt.edu.cn/uclass/',items:(value.assignments||[]).filter(item=>{
      const date=String(item.deadline||'').slice(0,10)
      return date>=start&&date<=end
    })}
  }
  reloadQM(changed=false) {
    if(!this.qmEnabled)return Promise.resolve(null)
    if(this.qmRead){if(changed)this.qmReadAgain=true;return this.qmRead}
    const revision=this.qmRevision
    const work=this.command('load_qmplus').then(value=>{
      if(this.live&&this.qmEnabled&&revision===this.qmRevision){if(value===null)this.resetNoticeSource('qmplus');this.acceptNewAssignments('qmplus',value,!this.qmRestored);this.qmRestored=true;this.publish({qm:value})}
      return value
    }).finally(()=>{if(this.qmRead===work){this.qmRead=null;if(this.qmReadAgain&&this.live&&this.qmEnabled&&revision===this.qmRevision){this.qmReadAgain=false;void this.reloadQM().catch(()=>{})}}})
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
  resetCloud(){this.cloudRevision++;this.cloudFlight=null;this.hydration=null;this.resetNoticeSource('ucloud');this.publish({courses:null,assignments:null,fetchedAt:'',cloudBusy:false,cloudError:'',cacheWarning:false})}
  clear(){this.browserSeen.clear();this.cloudEnabled=false;this.qmEnabled=false;this.resetCloud();this.qmRevision++;this.qmFlight=null;this.qmRead=null;this.resetNoticeSource('qmplus');this.publish({qm:null})}
  dispose(){this.cloudEnabled=false;this.qmEnabled=false;this.cloudRevision++;this.qmRevision++;this.live=false;this.listeners.clear()}
}
