package org.mytonwallet.app_air.walletcontext.helpers

/*class LauncherIconController {
    enum class LauncherIcon(
        val key: String,
        val icon: Int,
        val title: String
    ) {
        AIR(
            "Air",
            R.mipmap.ic_launcher_round,
            "Air"
        ),
        CLASSIC(
            "Classic",
            R.mipmap.ic_launcher_classic_round,
            "Classic"
        );

        private var componentName: ComponentName? = null

        fun getComponentName(ctx: Context): ComponentName? {
            if (componentName == null) {
                componentName =
                    ComponentName(
                        ctx.packageName,
                        "org.mytonwallet.app.$key"
                    )
            }
            return componentName
        }
    }

    companion object {
        fun tryFixLauncherIconIfNeeded(applicationContext: Context) {
            for (icon in LauncherIcon.entries) {
                if (isEnabled(applicationContext, icon)) {
                    return
                }
            }

            setIcon(applicationContext, LauncherIcon.CLASSIC)
        }

        fun isEnabled(applicationContext: Context, icon: LauncherIcon): Boolean {
            val i: Int =
                applicationContext.packageManager
                    .getComponentEnabledSetting(icon.getComponentName(applicationContext)!!)
            return i == PackageManager.COMPONENT_ENABLED_STATE_ENABLED || i == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && icon == LauncherIcon.CLASSIC
        }

        fun setIcon(applicationContext: Context, icon: LauncherIcon) {
            val pm: PackageManager = applicationContext.packageManager
            for (i in LauncherIcon.entries) {
                pm.setComponentEnabledSetting(
                    i.getComponentName(applicationContext)!!,
                    if (i == icon) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP
                )
            }
        }
    }
}
*/
