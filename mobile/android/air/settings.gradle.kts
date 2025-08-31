pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "MyTonWallet"
val airSubModulePath = extra["airSubModulePath"]

val subModules = listOf(
    "UIComponents",
    "UICreateWallet",
    "WalletContext",
    "WalletNative",
    "WalletCore",
    "UISettings",
    "UIPasscode",
    "UIHome",
    "UIAssets",
    "UIBrowser",
    "UITransaction",
    "OverScroll",
    "UISend",
    "UISwap",
    "UIInAppBrowser",
    "Icons",
    "AirAsFramework",
    "UIStake",
    "UITonConnect",
    "QRScan"
)

include(":app")
include("$airSubModulePath:vkryl:core")
include("$airSubModulePath:vkryl:android")
subModules.forEach { moduleName ->
    include("$airSubModulePath:$moduleName")
    project("$airSubModulePath:$moduleName").name = moduleName
}
include(":SubModules:Icons")
