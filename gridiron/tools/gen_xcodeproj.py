#!/usr/bin/env python3
"""
Generates PixelGridiron.xcodeproj from whatever is on disk.

A hand-maintained project.pbxproj is the usual way a Swift repository rots: a
file gets added, nobody adds it to the target, and the build fails somewhere
unrelated. This walks the source tree and regenerates the project, so the target
membership is a fact about the filesystem rather than something to remember.

    python3 tools/gen_xcodeproj.py

Object identifiers are the first 24 hex digits of an MD5 of a stable key, so
re-running produces a byte-identical file and a diff only shows real changes.
"""

import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_NAME = "PixelGridiron"
APP_DIR = "PixelGridiron"
TEST_DIR = "PixelGridironTests"
BUNDLE_ID = "com.example.pixelgridiron"
DEPLOYMENT_TARGET = "16.0"
SWIFT_VERSION = "5.0"

# Order matters only for readability; the compiler does not care.
SOURCE_GROUPS = ["App", "Core", "Render", "UI", "Scenes", "Audio", "Support"]


def uid(key):
    return hashlib.md5(key.encode("utf-8")).hexdigest()[:24].upper()


def collect():
    """Returns (app_sources, app_resources, test_sources), all repo-relative."""
    app_sources, app_resources = [], []
    for group in SOURCE_GROUPS:
        directory = os.path.join(ROOT, APP_DIR, group)
        if not os.path.isdir(directory):
            continue
        for name in sorted(os.listdir(directory)):
            path = "%s/%s/%s" % (APP_DIR, group, name)
            if name.endswith(".swift"):
                app_sources.append(path)
            elif name == "Info.plist":
                continue          # referenced by build setting, never compiled
            elif not name.startswith("."):
                app_resources.append(path)

    test_sources = []
    directory = os.path.join(ROOT, TEST_DIR)
    if os.path.isdir(directory):
        for name in sorted(os.listdir(directory)):
            if name.endswith(".swift"):
                test_sources.append("%s/%s" % (TEST_DIR, name))

    return app_sources, app_resources, test_sources


def file_type(path):
    if path.endswith(".swift"):
        return "sourcecode.swift"
    if path.endswith(".plist"):
        return "text.plist.xml"
    if path.endswith(".png"):
        return "image.png"
    if path.endswith(".md"):
        return "net.daringfireball.markdown"
    return "text"


def build_pbxproj():
    app_sources, app_resources, test_sources = collect()
    if not app_sources:
        sys.exit("no sources found under %s/ — run this from the repository" % APP_DIR)

    every_file = app_sources + app_resources + test_sources + ["%s/App/Info.plist" % APP_DIR]

    ref = {path: uid("ref:" + path) for path in every_file}
    build = {path: uid("build:" + path) for path in every_file}

    ids = {name: uid("obj:" + name) for name in [
        "project", "mainGroup", "productsGroup", "appGroup", "testGroup",
        "appTarget", "testTarget", "appProduct", "testProduct",
        "appSources", "appResources", "appFrameworks",
        "testSources", "testResources", "testFrameworks",
        "projectConfigList", "appConfigList", "testConfigList",
        "projectDebug", "projectRelease", "appDebug", "appRelease",
        "testDebug", "testRelease", "testDependency", "testProxy",
    ]}
    for group in SOURCE_GROUPS:
        ids["group:" + group] = uid("obj:group:" + group)

    out = []
    w = out.append

    w("// !$*UTF8*$!")
    w("{")
    w("\tarchiveVersion = 1;")
    w("\tclasses = {")
    w("\t};")
    w("\tobjectVersion = 56;")
    w("\tobjects = {")

    # ---- PBXBuildFile
    w("")
    w("/* Begin PBXBuildFile section */")
    for path in app_sources + app_resources + test_sources:
        w('\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };'
          % (build[path], os.path.basename(path), ref[path], os.path.basename(path)))
    w("/* End PBXBuildFile section */")

    # ---- PBXContainerItemProxy
    w("")
    w("/* Begin PBXContainerItemProxy section */")
    w("\t\t%s /* PBXContainerItemProxy */ = {" % ids["testProxy"])
    w("\t\t\tisa = PBXContainerItemProxy;")
    w("\t\t\tcontainerPortal = %s /* Project object */;" % ids["project"])
    w("\t\t\tproxyType = 1;")
    w("\t\t\tremoteGlobalIDString = %s;" % ids["appTarget"])
    w('\t\t\tremoteInfo = %s;' % PROJECT_NAME)
    w("\t\t};")
    w("/* End PBXContainerItemProxy section */")

    # ---- PBXFileReference
    w("")
    w("/* Begin PBXFileReference section */")
    for path in every_file:
        w('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; path = %s; sourceTree = "<group>"; };'
          % (ref[path], os.path.basename(path), file_type(path), os.path.basename(path)))
    w('\t\t%s /* %s.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = %s.app; sourceTree = BUILT_PRODUCTS_DIR; };'
      % (ids["appProduct"], PROJECT_NAME, PROJECT_NAME))
    w('\t\t%s /* %sTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = %sTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };'
      % (ids["testProduct"], PROJECT_NAME, PROJECT_NAME))
    w("/* End PBXFileReference section */")

    # ---- PBXFrameworksBuildPhase
    w("")
    w("/* Begin PBXFrameworksBuildPhase section */")
    for key, label in [("appFrameworks", PROJECT_NAME), ("testFrameworks", PROJECT_NAME + "Tests")]:
        w("\t\t%s /* Frameworks */ = {" % ids[key])
        w("\t\t\tisa = PBXFrameworksBuildPhase;")
        w("\t\t\tbuildActionMask = 2147483647;")
        w("\t\t\tfiles = (")
        w("\t\t\t);")
        w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        w("\t\t};")
        del label
    w("/* End PBXFrameworksBuildPhase section */")

    # ---- PBXGroup
    w("")
    w("/* Begin PBXGroup section */")

    w("\t\t%s = {" % ids["mainGroup"])
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w("\t\t\t\t%s /* %s */," % (ids["appGroup"], APP_DIR))
    w("\t\t\t\t%s /* %s */," % (ids["testGroup"], TEST_DIR))
    w("\t\t\t\t%s /* Products */," % ids["productsGroup"])
    w("\t\t\t);")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")

    w("\t\t%s /* Products */ = {" % ids["productsGroup"])
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w("\t\t\t\t%s /* %s.app */," % (ids["appProduct"], PROJECT_NAME))
    w("\t\t\t\t%s /* %sTests.xctest */," % (ids["testProduct"], PROJECT_NAME))
    w("\t\t\t);")
    w("\t\t\tname = Products;")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")

    present_groups = [g for g in SOURCE_GROUPS
                      if os.path.isdir(os.path.join(ROOT, APP_DIR, g))]

    w("\t\t%s /* %s */ = {" % (ids["appGroup"], APP_DIR))
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    for group in present_groups:
        w("\t\t\t\t%s /* %s */," % (ids["group:" + group], group))
    w("\t\t\t);")
    w("\t\t\tpath = %s;" % APP_DIR)
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")

    for group in present_groups:
        members = [p for p in every_file if p.startswith("%s/%s/" % (APP_DIR, group))]
        w("\t\t%s /* %s */ = {" % (ids["group:" + group], group))
        w("\t\t\tisa = PBXGroup;")
        w("\t\t\tchildren = (")
        for path in members:
            w("\t\t\t\t%s /* %s */," % (ref[path], os.path.basename(path)))
        w("\t\t\t);")
        w("\t\t\tpath = %s;" % group)
        w("\t\t\tsourceTree = \"<group>\";")
        w("\t\t};")

    w("\t\t%s /* %s */ = {" % (ids["testGroup"], TEST_DIR))
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    for path in test_sources:
        w("\t\t\t\t%s /* %s */," % (ref[path], os.path.basename(path)))
    w("\t\t\t);")
    w("\t\t\tpath = %s;" % TEST_DIR)
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")
    w("/* End PBXGroup section */")

    # ---- PBXNativeTarget
    w("")
    w("/* Begin PBXNativeTarget section */")
    w("\t\t%s /* %s */ = {" % (ids["appTarget"], PROJECT_NAME))
    w("\t\t\tisa = PBXNativeTarget;")
    w("\t\t\tbuildConfigurationList = %s;" % ids["appConfigList"])
    w("\t\t\tbuildPhases = (")
    w("\t\t\t\t%s /* Sources */," % ids["appSources"])
    w("\t\t\t\t%s /* Frameworks */," % ids["appFrameworks"])
    w("\t\t\t\t%s /* Resources */," % ids["appResources"])
    w("\t\t\t);")
    w("\t\t\tbuildRules = (")
    w("\t\t\t);")
    w("\t\t\tdependencies = (")
    w("\t\t\t);")
    w("\t\t\tname = %s;" % PROJECT_NAME)
    w("\t\t\tproductName = %s;" % PROJECT_NAME)
    w("\t\t\tproductReference = %s;" % ids["appProduct"])
    w("\t\t\tproductType = \"com.apple.product-type.application\";")
    w("\t\t};")

    w("\t\t%s /* %sTests */ = {" % (ids["testTarget"], PROJECT_NAME))
    w("\t\t\tisa = PBXNativeTarget;")
    w("\t\t\tbuildConfigurationList = %s;" % ids["testConfigList"])
    w("\t\t\tbuildPhases = (")
    w("\t\t\t\t%s /* Sources */," % ids["testSources"])
    w("\t\t\t\t%s /* Frameworks */," % ids["testFrameworks"])
    w("\t\t\t\t%s /* Resources */," % ids["testResources"])
    w("\t\t\t);")
    w("\t\t\tbuildRules = (")
    w("\t\t\t);")
    w("\t\t\tdependencies = (")
    w("\t\t\t\t%s /* PBXTargetDependency */," % ids["testDependency"])
    w("\t\t\t);")
    w("\t\t\tname = %sTests;" % PROJECT_NAME)
    w("\t\t\tproductName = %sTests;" % PROJECT_NAME)
    w("\t\t\tproductReference = %s;" % ids["testProduct"])
    w("\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";")
    w("\t\t};")
    w("/* End PBXNativeTarget section */")

    # ---- PBXProject
    w("")
    w("/* Begin PBXProject section */")
    w("\t\t%s /* Project object */ = {" % ids["project"])
    w("\t\t\tisa = PBXProject;")
    w("\t\t\tattributes = {")
    w("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    w("\t\t\t\tLastSwiftUpdateCheck = 1500;")
    w("\t\t\t\tLastUpgradeCheck = 1500;")
    w("\t\t\t\tTargetAttributes = {")
    w("\t\t\t\t\t%s = {" % ids["appTarget"])
    w("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
    w("\t\t\t\t\t};")
    w("\t\t\t\t\t%s = {" % ids["testTarget"])
    w("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
    w("\t\t\t\t\t\tTestTargetID = %s;" % ids["appTarget"])
    w("\t\t\t\t\t};")
    w("\t\t\t\t};")
    w("\t\t\t};")
    w("\t\t\tbuildConfigurationList = %s;" % ids["projectConfigList"])
    w("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    w("\t\t\tdevelopmentRegion = en;")
    w("\t\t\thasScannedForEncodings = 0;")
    w("\t\t\tknownRegions = (")
    w("\t\t\t\ten,")
    w("\t\t\t\tBase,")
    w("\t\t\t);")
    w("\t\t\tmainGroup = %s;" % ids["mainGroup"])
    w("\t\t\tproductRefGroup = %s /* Products */;" % ids["productsGroup"])
    w("\t\t\tprojectDirPath = \"\";")
    w("\t\t\tprojectRoot = \"\";")
    w("\t\t\ttargets = (")
    w("\t\t\t\t%s /* %s */," % (ids["appTarget"], PROJECT_NAME))
    w("\t\t\t\t%s /* %sTests */," % (ids["testTarget"], PROJECT_NAME))
    w("\t\t\t);")
    w("\t\t};")
    w("/* End PBXProject section */")

    # ---- PBXResourcesBuildPhase
    w("")
    w("/* Begin PBXResourcesBuildPhase section */")
    w("\t\t%s /* Resources */ = {" % ids["appResources"])
    w("\t\t\tisa = PBXResourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    for path in app_resources:
        w("\t\t\t\t%s /* %s in Resources */," % (build[path], os.path.basename(path)))
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("\t\t%s /* Resources */ = {" % ids["testResources"])
    w("\t\t\tisa = PBXResourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXResourcesBuildPhase section */")

    # ---- PBXSourcesBuildPhase
    w("")
    w("/* Begin PBXSourcesBuildPhase section */")
    for key, files in [("appSources", app_sources), ("testSources", test_sources)]:
        w("\t\t%s /* Sources */ = {" % ids[key])
        w("\t\t\tisa = PBXSourcesBuildPhase;")
        w("\t\t\tbuildActionMask = 2147483647;")
        w("\t\t\tfiles = (")
        for path in files:
            w("\t\t\t\t%s /* %s in Sources */," % (build[path], os.path.basename(path)))
        w("\t\t\t);")
        w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        w("\t\t};")
    w("/* End PBXSourcesBuildPhase section */")

    # ---- PBXTargetDependency
    w("")
    w("/* Begin PBXTargetDependency section */")
    w("\t\t%s /* PBXTargetDependency */ = {" % ids["testDependency"])
    w("\t\t\tisa = PBXTargetDependency;")
    w("\t\t\ttarget = %s /* %s */;" % (ids["appTarget"], PROJECT_NAME))
    w("\t\t\ttargetProxy = %s /* PBXContainerItemProxy */;" % ids["testProxy"])
    w("\t\t};")
    w("/* End PBXTargetDependency section */")

    # ---- XCBuildConfiguration
    shared_project = [
        "ALWAYS_SEARCH_USER_PATHS = NO;",
        "CLANG_ENABLE_MODULES = YES;",
        "CLANG_ENABLE_OBJC_ARC = YES;",
        "COPY_PHASE_STRIP = NO;",
        "ENABLE_STRICT_OBJC_MSGSEND = YES;",
        "GCC_C_LANGUAGE_STANDARD = gnu11;",
        "GCC_NO_COMMON_BLOCKS = YES;",
        "IPHONEOS_DEPLOYMENT_TARGET = %s;" % DEPLOYMENT_TARGET,
        "SDKROOT = iphoneos;",
        "SWIFT_VERSION = %s;" % SWIFT_VERSION,
    ]

    def emit_config(key, name, settings):
        w("\t\t%s /* %s */ = {" % (ids[key], name))
        w("\t\t\tisa = XCBuildConfiguration;")
        w("\t\t\tbuildSettings = {")
        for line in settings:
            w("\t\t\t\t%s" % line)
        w("\t\t\t};")
        w("\t\t\tname = %s;" % name)
        w("\t\t};")

    w("")
    w("/* Begin XCBuildConfiguration section */")
    emit_config("projectDebug", "Debug", shared_project + [
        "DEBUG_INFORMATION_FORMAT = dwarf;",
        "ENABLE_TESTABILITY = YES;",
        "GCC_OPTIMIZATION_LEVEL = 0;",
        'GCC_PREPROCESSOR_DEFINITIONS = ("DEBUG=1", "$(inherited)");',
        "MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;",
        "ONLY_ACTIVE_ARCH = YES;",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;",
        "SWIFT_OPTIMIZATION_LEVEL = \"-Onone\";",
    ])
    emit_config("projectRelease", "Release", shared_project + [
        "DEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";",
        "ENABLE_NS_ASSERTIONS = NO;",
        "MTL_ENABLE_DEBUG_INFO = NO;",
        "SWIFT_COMPILATION_MODE = wholemodule;",
        "SWIFT_OPTIMIZATION_LEVEL = \"-O\";",
        "VALIDATE_PRODUCT = YES;",
    ])

    app_settings = [
        "ASSETCATALOG_COMPILER_APPICON_NAME = \"\";",
        "CODE_SIGN_STYLE = Automatic;",
        "CURRENT_PROJECT_VERSION = 1;",
        "DEVELOPMENT_TEAM = \"\";",
        "GENERATE_INFOPLIST_FILE = NO;",
        "INFOPLIST_FILE = \"%s/App/Info.plist\";" % APP_DIR,
        "LD_RUNPATH_SEARCH_PATHS = (\"$(inherited)\", \"@executable_path/Frameworks\");",
        "MARKETING_VERSION = 1.0;",
        "PRODUCT_BUNDLE_IDENTIFIER = %s;" % BUNDLE_ID,
        "PRODUCT_NAME = \"$(TARGET_NAME)\";",
        "SWIFT_EMIT_LOC_STRINGS = YES;",
        "TARGETED_DEVICE_FAMILY = \"1,2\";",
    ]
    emit_config("appDebug", "Debug", app_settings)
    emit_config("appRelease", "Release", app_settings)

    test_settings = [
        "ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = YES;",
        "BUNDLE_LOADER = \"$(TEST_HOST)\";",
        "CODE_SIGN_STYLE = Automatic;",
        "CURRENT_PROJECT_VERSION = 1;",
        "DEVELOPMENT_TEAM = \"\";",
        "GENERATE_INFOPLIST_FILE = YES;",
        "MARKETING_VERSION = 1.0;",
        "PRODUCT_BUNDLE_IDENTIFIER = %s.tests;" % BUNDLE_ID,
        "PRODUCT_NAME = \"$(TARGET_NAME)\";",
        "TARGETED_DEVICE_FAMILY = \"1,2\";",
        "TEST_HOST = \"$(BUILT_PRODUCTS_DIR)/%s.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/%s\";"
        % (PROJECT_NAME, PROJECT_NAME),
    ]
    emit_config("testDebug", "Debug", test_settings)
    emit_config("testRelease", "Release", test_settings)
    w("/* End XCBuildConfiguration section */")

    # ---- XCConfigurationList
    w("")
    w("/* Begin XCConfigurationList section */")
    for key, debug, release, label in [
        ("projectConfigList", "projectDebug", "projectRelease", "PBXProject \"%s\"" % PROJECT_NAME),
        ("appConfigList", "appDebug", "appRelease", "PBXNativeTarget \"%s\"" % PROJECT_NAME),
        ("testConfigList", "testDebug", "testRelease", "PBXNativeTarget \"%sTests\"" % PROJECT_NAME),
    ]:
        w("\t\t%s /* Build configuration list for %s */ = {" % (ids[key], label))
        w("\t\t\tisa = XCConfigurationList;")
        w("\t\t\tbuildConfigurations = (")
        w("\t\t\t\t%s /* Debug */," % ids[debug])
        w("\t\t\t\t%s /* Release */," % ids[release])
        w("\t\t\t);")
        w("\t\t\tdefaultConfigurationIsVisible = 0;")
        w("\t\t\tdefaultConfigurationName = Release;")
        w("\t\t};")
    w("/* End XCConfigurationList section */")

    w("\t};")
    w("\trootObject = %s /* Project object */;" % ids["project"])
    w("}")

    return "\n".join(out) + "\n", ids


def build_scheme(ids):
    return """<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app}"
               BuildableName = "{name}.app"
               BlueprintName = "{name}"
               ReferencedContainer = "container:{name}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{tests}"
               BuildableName = "{name}Tests.xctest"
               BlueprintName = "{name}Tests"
               ReferencedContainer = "container:{name}.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app}"
            BuildableName = "{name}.app"
            BlueprintName = "{name}"
            ReferencedContainer = "container:{name}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app}"
            BuildableName = "{name}.app"
            BlueprintName = "{name}"
            ReferencedContainer = "container:{name}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
""".replace("{app}", ids["appTarget"]).replace("{tests}", ids["testTarget"]).replace("{name}", PROJECT_NAME)


def main():
    pbxproj, ids = build_pbxproj()

    project_dir = os.path.join(ROOT, PROJECT_NAME + ".xcodeproj")
    scheme_dir = os.path.join(project_dir, "xcshareddata", "xcschemes")
    os.makedirs(scheme_dir, exist_ok=True)

    with open(os.path.join(project_dir, "project.pbxproj"), "w") as handle:
        handle.write(pbxproj)
    with open(os.path.join(scheme_dir, PROJECT_NAME + ".xcscheme"), "w") as handle:
        handle.write(build_scheme(ids))

    app_sources, app_resources, test_sources = collect()
    print("wrote %s" % os.path.relpath(project_dir, ROOT))
    print("  %d app sources, %d resources, %d test sources"
          % (len(app_sources), len(app_resources), len(test_sources)))


if __name__ == "__main__":
    main()
