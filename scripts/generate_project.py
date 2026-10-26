#!/usr/bin/env python3
"""Reproducible Xcode project generator; Python standard library only."""
from pathlib import Path
import hashlib, json, plistlib, struct, zlib
root = Path(__file__).resolve().parents[1]
def ident(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def quote(s): return json.dumps(s, ensure_ascii=False)
objects = {}
def add(name, value):
    key = ident(name); objects[key] = value; return key
def refs(xs): return '(' + ', '.join(xs) + (',' if xs else '') + ')'
source_paths = sorted(str(p.relative_to(root)) for folder in ['App', 'Sources/LedgerCore'] for p in (root/folder).glob('*.swift'))
source_refs, build_refs = [], []
for path in source_paths:
    f = add(path, '{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = '+quote(path)+'; sourceTree = SOURCE_ROOT; }')
    source_refs.append(f)
    build_refs.append(add('build:'+path, '{isa = PBXBuildFile; fileRef = '+f+'; }'))
resource_refs, resource_builds = [], []
for path, typ in [('App/Assets.xcassets', 'folder.assetcatalog'), ('App/PrivacyInfo.xcprivacy','text.xml'), ('App/Fonts/NotoSerifSC.ttf','file'), ('App/Fonts/OFL.txt','text')]:
    f = add(path, '{isa = PBXFileReference; lastKnownFileType = '+typ+'; path = '+quote(path)+'; sourceTree = SOURCE_ROOT; }')
    resource_refs.append(f); resource_builds.append(add('build:'+path, '{isa = PBXBuildFile; fileRef = '+f+'; }'))
product = add('product','{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = LocalLedger.app; sourceTree = BUILT_PRODUCTS_DIR; }')
products = add('products','{isa = PBXGroup; children = '+refs([product])+'; name = Products; sourceTree = "<group>"; }')
group = add('main','{isa = PBXGroup; children = '+refs(source_refs+resource_refs+[products])+'; sourceTree = "<group>"; }')
sources = add('sources','{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = '+refs(build_refs)+'; runOnlyForDeploymentPostprocessing = 0; }')
resources = add('resources','{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = '+refs(resource_builds)+'; runOnlyForDeploymentPostprocessing = 0; }')
frameworks = add('frameworks','{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }')
base = {'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'17.0','CLANG_ENABLE_MODULES':'YES','SWIFT_VERSION':'5.0','SWIFT_STRICT_CONCURRENCY':'complete','SWIFT_EMIT_LOC_STRINGS':'YES','TARGETED_DEVICE_FAMILY':'1','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SUPPORTS_MACCATALYST':'NO','SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD':'NO','SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD':'NO','CODE_SIGN_STYLE':'Automatic','PRODUCT_BUNDLE_IDENTIFIER':'com.example.LocalLedger','PRODUCT_NAME':'$(TARGET_NAME)','INFOPLIST_FILE':'App/Info.plist','GENERATE_INFOPLIST_FILE':'NO','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','MARKETING_VERSION':'1.9','CURRENT_PROJECT_VERSION':'11','ENABLE_USER_SCRIPT_SANDBOXING':'YES'}
def config(name, settings):
    return add(name, '{isa = XCBuildConfiguration; buildSettings = {' + ''.join(k+' = '+quote(v)+'; ' for k,v in settings.items())+'}; name = '+name.split(':')[-1]+'; }')
configs=[]
for mode in ['Debug','Release']:
    settings=dict(base, SWIFT_OPTIMIZATION_LEVEL='-Onone' if mode=='Debug' else '-O', DEBUG_INFORMATION_FORMAT='dwarf' if mode=='Debug' else 'dwarf-with-dsym')
    if mode=='Debug': settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'; settings['ENABLE_TESTABILITY']='YES'
    configs.append(config('target:'+mode,settings))
target_config=add('target-config','{isa = XCConfigurationList; buildConfigurations = '+refs(configs)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }')
project_config=add('project-config','{isa = XCConfigurationList; buildConfigurations = '+refs([config('project:Debug',{}),config('project:Release',{})])+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }')
target=add('target','{isa = PBXNativeTarget; buildConfigurationList = '+target_config+'; buildPhases = '+refs([sources,frameworks,resources])+'; buildRules = (); dependencies = (); name = LocalLedger; productName = LocalLedger; productReference = '+product+'; productType = "com.apple.product-type.application"; }')
# UI regression target runs only on a simulator selected by the developer.
ui_file=add('ui-file','{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "UITests/LocalLedgerUITests.swift"; sourceTree = SOURCE_ROOT; }')
ui_build=add('ui-build','{isa = PBXBuildFile; fileRef = '+ui_file+'; }')
ui_sources=add('ui-sources','{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = '+refs([ui_build]+[ident('build:'+p) for p in source_paths if p.startswith('Sources/LedgerCore/') or p=='App/ReceiptOCR.swift'])+'; runOnlyForDeploymentPostprocessing = 0; }')
ui_product=add('ui-product','{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = LocalLedgerUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }')
ui_configs=[]
for mode in ['Debug','Release']:
    ui_configs.append(config('ui:'+mode, {'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SWIFT_VERSION':'5.0','ALWAYS_SEARCH_USER_PATHS':'NO','TARGETED_DEVICE_FAMILY':'1','PRODUCT_BUNDLE_IDENTIFIER':'com.example.LocalLedgerUITests','PRODUCT_NAME':'$(TARGET_NAME)','GENERATE_INFOPLIST_FILE':'YES','TEST_TARGET_NAME':'LocalLedger','CODE_SIGN_STYLE':'Automatic'}))
ui_config=add('ui-config','{isa = XCConfigurationList; buildConfigurations = '+refs(ui_configs)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }')
proxy=add('ui-proxy','{isa = PBXContainerItemProxy; containerPortal = '+ident('project')+'; proxyType = 1; remoteGlobalIDString = '+target+'; remoteInfo = LocalLedger; }')
dependency=add('ui-dependency','{isa = PBXTargetDependency; target = '+target+'; targetProxy = '+proxy+'; }')
ui_target=add('ui-target','{isa = PBXNativeTarget; buildConfigurationList = '+ui_config+'; buildPhases = '+refs([ui_sources])+'; buildRules = (); dependencies = '+refs([dependency])+'; name = LocalLedgerUITests; productName = LocalLedgerUITests; productReference = '+ui_product+'; productType = "com.apple.product-type.bundle.ui-testing"; }')
objects[group]=objects[group].replace(refs(source_refs+resource_refs+[products]),refs(source_refs+resource_refs+[ui_file,products]))
objects[products]=objects[products].replace(refs([product]),refs([product,ui_product]))
project=add('project','{isa = PBXProject; attributes = {BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; }; buildConfigurationList = '+project_config+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = ("zh-Hans", en, Base); mainGroup = '+group+'; productRefGroup = '+products+'; projectDirPath = ""; projectRoot = ""; targets = '+refs([target,ui_target])+'; }')
(root/'LocalLedger.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+ '\n'.join(k+' = '+v+';' for k,v in objects.items())+'\n}; rootObject = '+project+'; }\n')
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="LocalLedger.app" BlueprintName="LocalLedger" ReferencedContainer="container:LocalLedger.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ui_target}" BuildableName="LocalLedgerUITests.xctest" BlueprintName="LocalLedgerUITests" ReferencedContainer="container:LocalLedger.xcodeproj"/></TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="LocalLedger.app" BlueprintName="LocalLedger" ReferencedContainer="container:LocalLedger.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="LocalLedger.app" BlueprintName="LocalLedger" ReferencedContainer="container:LocalLedger.xcodeproj"/></BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(root/'LocalLedger.xcodeproj/xcshareddata/xcschemes/LocalLedger.xcscheme').write_text(scheme)
info={'CFBundleDevelopmentRegion':'zh-Hans','CFBundleDisplayName':'账本','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'$(PRODUCT_NAME)','CFBundlePackageType':'APPL','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)','LSRequiresIPhoneOS':True,'UILaunchScreen':{'UIColorName':'LaunchPaper'},'UIAppFonts':['NotoSerifSC.ttf'],'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait'],'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False}}
(root/'App/Info.plist').write_bytes(plistlib.dumps(info))
privacy={'NSPrivacyTracking':False,'NSPrivacyTrackingDomains':[],'NSPrivacyCollectedDataTypes':[],'NSPrivacyAccessedAPITypes':[{'NSPrivacyAccessedAPIType':'NSPrivacyAccessedAPICategoryFileTimestamp','NSPrivacyAccessedAPITypeReasons':['C617.1']}]}
(root/'App/PrivacyInfo.xcprivacy').write_bytes(plistlib.dumps(privacy))
assets=root/'App/Assets.xcassets'; icon=assets/'AppIcon.appiconset'; icon.mkdir(parents=True,exist_ok=True)
(assets/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}))
(icon/'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}},indent=2))
# Render the original production pen paths at full resolution; no brand artwork.
import subprocess
import tempfile
with tempfile.NamedTemporaryFile(mode='w', suffix='.swift') as render:
    render.write((root/'App/Calligraphy.swift').read_text().split('struct HandwrittenLedger:')[0])
    render.write((root/'scripts/render_icon.swift').read_text())
    render.flush()
    subprocess.run(['swift', render.name, str(icon/'AppIcon.png')], check=True)
print(f'Generated project with {len(source_paths)} Swift source files.')

launch_color=assets/'LaunchPaper.colorset'; launch_color.mkdir(exist_ok=True)
(launch_color/'Contents.json').write_text(json.dumps({'colors':[
 {'idiom':'universal','color':{'color-space':'srgb','components':{'red':'0.975','green':'0.966','blue':'0.941','alpha':'1.0'}}},
 {'idiom':'universal','appearances':[{'appearance':'luminosity','value':'dark'}],'color':{'color-space':'srgb','components':{'red':'0.13','green':'0.10','blue':'0.08','alpha':'1.0'}}}
], 'info':{'author':'xcode','version':1}}, indent=2))
