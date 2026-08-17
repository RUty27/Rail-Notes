/**
 * Registers SpeechRecognitionPlugin.swift in App.xcodeproj.
 *
 * `npx cap add ios` regenerates the project from a template that uses classic
 * Xcode groups, so a Swift file sitting on disk is invisible to the build.
 * This script wires it into all four places the pbxproj needs it, and is safe
 * to re-run — it bails out if the reference is already there.
 *
 * Run it after any `cap add ios`:  node scripts/add-ios-plugin.js
 */
const fs = require("fs");
const path = require("path");

const PBX = path.join(__dirname, "..", "ios", "App", "App.xcodeproj", "project.pbxproj");
const FILE = "SpeechRecognitionPlugin.swift";
const FILE_REF = "AA11BB22CC33DD44EE550001";
const BUILD_REF = "AA11BB22CC33DD44EE550002";

/* anchor on SceneDelegate, which the template always contains */
const A_BUILD = "9582B6832FE993A70072D4E8 /* SceneDelegate.swift in Sources */ = {isa = PBXBuildFile; fileRef = 9582B6822FE993A50072D4E8 /* SceneDelegate.swift */; };";
const A_FILEREF = "9582B6822FE993A50072D4E8 /* SceneDelegate.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SceneDelegate.swift; sourceTree = \"<group>\"; };";
const A_CHILD = "9582B6822FE993A50072D4E8 /* SceneDelegate.swift */,";
const A_SOURCE = "9582B6832FE993A70072D4E8 /* SceneDelegate.swift in Sources */,";

if (!fs.existsSync(PBX)) {
  console.error("No project.pbxproj — run `npx cap add ios` first.");
  process.exit(1);
}
let s = fs.readFileSync(PBX, "utf8");

if (s.includes(FILE)) {
  console.log(`${FILE} is already registered — nothing to do.`);
  process.exit(0);
}

const edits = [
  [A_BUILD, `${A_BUILD}\n\t\t${BUILD_REF} /* ${FILE} in Sources */ = {isa = PBXBuildFile; fileRef = ${FILE_REF} /* ${FILE} */; };`],
  [A_FILEREF, `${A_FILEREF}\n\t\t${FILE_REF} /* ${FILE} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ${FILE}; sourceTree = "<group>"; };`],
  [A_CHILD, `${A_CHILD}\n\t\t\t\t${FILE_REF} /* ${FILE} */,`],
  [A_SOURCE, `${A_SOURCE}\n\t\t\t\t${BUILD_REF} /* ${FILE} in Sources */,`]
];

for (const [needle, replacement] of edits) {
  const hits = s.split(needle).length - 1;
  if (hits !== 1) {
    console.error(`Expected exactly 1 match, found ${hits}, for:\n  ${needle.slice(0, 70)}…`);
    console.error("The Capacitor iOS template changed. Fix this script rather than guessing.");
    process.exit(1);
  }
  s = s.replace(needle, replacement);
}

fs.writeFileSync(PBX, s);
console.log(`Registered ${FILE} in App.xcodeproj (4 references added).`);
