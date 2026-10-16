import Foundation

enum AuthKeychain { static func read() throws -> String? { "fixture" } }
@MainActor enum GitHubCloud {
  static func failure() -> NSError { NSError(domain:"fixture", code:1) }
  static func request(_ path:String, token:String) async throws -> Any { throw failure() }
  static func call(_ kind:String, path:String, args:[String:Any]) async throws -> Any { throw failure() }
}

@main struct SettingsCheck {
  @MainActor static func main() async throws {
    var rows:[[String:Any]] = [
      ["machineId":"m1","localProjectId":"same","ownerUserId":"owner","sharedWithTeam":false,"updatedAt":1.0],
      ["machineId":"m2","localProjectId":"same","ownerUserId":"teammate","sharedWithTeam":true,"updatedAt":1.0]
    ]
    var writes=0,failWrite=false,failReadbackAfter:Int?=nil
    let call:WorkspaceSettingsCloud.Call = { kind,path,args in
      if kind=="query" {
        if let after=failReadbackAfter, writes>=after {throw GitHubCloud.failure()}
        return rows
      }
      precondition(path=="localProjects:setLocalProjectSharedWithTeam")
      writes += 1
      if failWrite {throw GitHubCloud.failure()}
      let index=rows.firstIndex {$0["machineId"] as? String==args["machineId"] as? String}!
      rows[index]["sharedWithTeam"]=args["sharedWithTeam"]
      return ["success":true,"sharedWithTeam":args["sharedWithTeam"]!]
    }
    let read=try await WorkspaceSettingsCloud.execute(["page":"projects","action":"list"],workspace:"w",user:"owner",call:call)
    precondition((read["rows"] as? [[String:Any]])?.count==2 && writes==0)
    let target:[String:Any] = ["page":"projects","action":"set","machineId":"m2","localProjectId":"same","sharedWithTeam":false]
    do { _=try await WorkspaceSettingsCloud.execute(target,workspace:"w",user:"owner",call:call);fatalError("foreign write allowed") } catch {}
    precondition(writes==0)
    var own=target;own["machineId"]="m1";own["sharedWithTeam"]=true
    let saved=try await WorkspaceSettingsCloud.execute(own,workspace:"w",user:"owner",call:call)
    precondition(writes==1 && (saved["rows"] as? [[String:Any]])?[0]["sharedWithTeam"] as? Bool==true)
    precondition(rows[1]["sharedWithTeam"] as? Bool==true)
    failWrite=true
    do {_=try await WorkspaceSettingsCloud.execute(own,workspace:"w",user:"owner",call:call);fatalError("unknown write reported success")} catch {}
    precondition(writes==2,"Unknown writes must never replay")
    failWrite=false;failReadbackAfter=writes+1
    do {_=try await WorkspaceSettingsCloud.execute(own,workspace:"w",user:"owner",call:call);fatalError("failed readback reported success")} catch {}
    precondition(writes==3, "Readback failure must happen after the mutation")
    failReadbackAfter=nil
    var missing=own;missing["localProjectId"]="unregistered"
    do {_=try await WorkspaceSettingsCloud.execute(missing,workspace:"w",user:"owner",call:call);fatalError("unregistered write allowed")} catch {}
    print("Owner fencing, machine identity, readback and uncertain-write behavior passed")
  }
}
