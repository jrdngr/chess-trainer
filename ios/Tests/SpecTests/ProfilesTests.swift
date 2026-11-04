import Foundation
import Model
import Testing

/// A fresh list is one profile, Main, and every profile saves in its own folder.
@Test func firstProfileIsMain() {
  let list = ProfileList()
  #expect(list.activeProfile == Profile(id: ProfileList.mainId, name: "Main"))
  #expect(ProfileList.savePath(ProfileList.mainId) == "profiles/main/playbook.json")
  #expect(ProfileList.savePath("abc") == "profiles/abc/playbook.json")
}

/// A missing profiles.json (every install before profiles) decodes to just Main, active.
@Test func emptyProfilesFileIsMain() throws {
  let list = try JSONDecoder().decode(ProfileList.self, from: Data("{}".utf8))
  #expect(list == ProfileList())
}

/// A saved active id that no longer exists falls back to the first profile.
@Test func unknownActiveFallsBack() throws {
  let json = #"{"profiles":[{"id":"a","name":"A"},{"id":"b","name":"B"}],"active":"gone"}"#
  let list = try JSONDecoder().decode(ProfileList.self, from: Data(json.utf8))
  #expect(list.active == "a")
}

@Test func addingSwitchesAndNamesBlank() {
  var list = ProfileList()
  list.add("  Fresh  ", id: "f")
  #expect(list.active == "f")
  #expect(list.activeProfile.name == "Fresh")
  list.add("Profile 3", id: "x")
  // Blank takes the next free "Profile N": 4 profiles now, "Profile 3" is taken.
  list.add("   ", id: "y")
  #expect(list.activeProfile.name == "Profile 4")
}

@Test func renameIgnoresBlank() {
  var list = ProfileList()
  list.rename(ProfileList.mainId, " ")
  #expect(list.activeProfile.name == "Main")
  list.rename(ProfileList.mainId, "Long term")
  #expect(list.activeProfile.name == "Long term")
}

/// The last profile can't be removed; removing the active one moves to its neighbor.
@Test func removingProfiles() {
  var list = ProfileList()
  let removedLast = list.remove(ProfileList.mainId)
  #expect(!removedLast)
  list.add("B", id: "b")
  list.add("C", id: "c")
  list.activate("b")
  let removedB = list.remove("b")
  #expect(removedB)
  #expect(list.active == "c")
  let removedC = list.remove("c")
  #expect(removedC)
  #expect(list.active == ProfileList.mainId)
  #expect(list.profiles.map(\.id) == [ProfileList.mainId])
}

@Test func removingOtherKeepsActive() {
  var list = ProfileList()
  list.add("B", id: "b")
  let removedMain = list.remove(ProfileList.mainId)
  #expect(removedMain)
  #expect(list.active == "b")
}
