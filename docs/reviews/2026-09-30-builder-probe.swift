// Synthetic read-only audit probe; see 2026-09-30-progress-foundation-audit.md F01/F03/F04.
// Compile with SceneRecord plus CaptureLog.swift and SceneRecordBuilder.swift in an external scratch directory.
import Foundation
import SceneRecord
let identity:[Double] = [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
let intrinsics:[Double] = [1000,0,0,0,1000,0,500,500,1]
let start=Date(timeIntervalSince1970:1790000000)
var normal=identity; normal[12]=1
let frames=[FrameSample(frameID:"f0",t:0,cameraTransform:identity,intrinsics:intrinsics,trackingState:"limited:initializing",lensOffsetM:0,hasSceneDepth:false,exposureOffset:0),FrameSample(frameID:"f1",t:1,cameraTransform:normal,intrinsics:intrinsics,trackingState:"normal",lensOffsetM:0,hasSceneDepth:false,exposureOffset:0)]
let log=CaptureLog(sessionID:"synthetic-audit",startedAt:start,endedAt:start.addingTimeInterval(2),timezone:TimeZone(identifier:"Australia/Melbourne")!,device:DeviceInfo(model:"synthetic",os:"iOS 27.0",lidar:false,sceneDepth:false,geoTracking:"unavailable"),appVersion:"0",appBuild:"0",targetLabel:"synthetic",targetHeightM:nil,frames:frames,heading:HeadingSample(trueHeading:-1,magneticHeading:10,headingAccuracy:5,sampledAt:start),location:nil)
let record=try SceneRecordBuilder.build(log,sceneID:"PR-AUDIT")
let obj=try JSONSerialization.jsonObject(with:record.encoded()) as! [String:Any]
let north=obj["north"] as! [String:Any]
print("INVALID_TRUE_HEADING:",(north["candidates"] as! [[String:Any]])[0])
let session=obj["capture_session"] as! [String:Any]
print("EXPORTED_ANCHOR:",(session["viewpoint_lock"] as! [String:Any])["anchor_world"]!)
print("SECOND_POSITION_AND_OFFSET:",frames[1].position,frames[1].lensOffsetM)
let id1=SceneRecordBuilder.sceneID(date:start,sequence:1,timezone:log.timezone)
let id2=SceneRecordBuilder.sceneID(date:start.addingTimeInterval(120),sequence:1,timezone:log.timezone)
print("TWO_NEW_VIEW_IDS:",id1,id2,"COLLISION:",id1==id2)
