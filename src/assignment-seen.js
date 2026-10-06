// Browser preview has no native cache. Keep only bounded business IDs, never credentials.
export class AssignmentSeen {
  constructor(storage){
    if(storage===undefined&&typeof window!=='undefined')try{storage=window.localStorage}catch{}
    this.storage=storage;this.records=new Map()
  }
  observe(source,owner,term,ids,{restore=false,partial=false}={}) {
    if(partial)return []
    const key=`wts-assignment-seen:${source}`
    let record=this.records.get(key)
    if(!record){try{record=JSON.parse(this.storage?.getItem(key)||'null')}catch{}}
    if(!record||record.owner!==owner||record.term!==term||!Array.isArray(record.ids)||record.ids.length>20000)record={owner,term,ids:[],baseline:false,saturated:false}
    const seen=new Set(record.ids),fresh=[]
    for(const id of ids){if(seen.has(id))continue;if(seen.size>=20000){record.saturated=true;break}seen.add(id);if(record.baseline&&!restore&&!record.saturated)fresh.push(id)}
    record.ids=[...seen];record.baseline=true;this.records.set(key,record)
    // Never show an alert that cannot be recorded across browser restarts.
    if(!this.storage&&typeof window!=='undefined')return []
    try{this.storage?.setItem(key,JSON.stringify(record))}catch{return []}
    return fresh
  }
  clear(){this.records.clear();for(const source of ['ucloud','qmplus'])try{this.storage?.removeItem(`wts-assignment-seen:${source}`)}catch{}}
}
