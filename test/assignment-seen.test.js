import assert from 'node:assert/strict'
import test from 'node:test'
import {AssignmentSeen} from '../src/assignment-seen.js'
const storage=()=>{const values=new Map();return {getItem:key=>values.get(key),setItem:(key,value)=>values.set(key,value),removeItem:key=>values.delete(key)}}
test('persisted seen IDs survive edits, disappearance and restart, scoped by source owner and term',()=>{
  const disk=storage();let seen=new AssignmentSeen(disk)
  assert.deepEqual(seen.observe('ucloud','owner','term',['a']),[])
  assert.deepEqual(seen.observe('ucloud','owner','term',['a','b']),['b'])
  seen=new AssignmentSeen(disk)
  assert.deepEqual(seen.observe('ucloud','owner','term',[],{restore:true}),[])
  assert.deepEqual(seen.observe('ucloud','owner','term',['a','b']),[])
  assert.deepEqual(seen.observe('qmplus','owner','term',['a']),[])
  assert.deepEqual(seen.observe('ucloud','other','term',['a','b','c']),[])
  assert.deepEqual(seen.observe('ucloud','other','next',['a','b','c','d']),[])
  seen.clear();assert.deepEqual(new AssignmentSeen(disk).observe('ucloud','other','next',['e']),[])
})
test('partial QM snapshots cannot seed a baseline or consume new IDs',()=>{
  const seen=new AssignmentSeen(storage())
  assert.deepEqual(seen.observe('qmplus','owner','term',['partial'],{partial:true}),[])
  assert.deepEqual(seen.observe('qmplus','owner','term',['a']),[])
  assert.deepEqual(seen.observe('qmplus','owner','term',['a','b'],{partial:true}),[])
  assert.deepEqual(seen.observe('qmplus','owner','term',['a','b']),['b'])
})
