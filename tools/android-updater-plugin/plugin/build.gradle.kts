plugins {
	id("com.android.library")
}

val pluginName = "XiuxianUpdater"

android {
	namespace = "com.micjason.xiuxian.updater"
	compileSdk = 35

	buildFeatures {
		buildConfig = true
	}

	defaultConfig {
		minSdk = 24
		buildConfigField("String", "GODOT_PLUGIN_NAME", "\"$pluginName\"")
		setProperty("archivesBaseName", pluginName)
	}

	buildTypes {
		release {
			isMinifyEnabled = false
		}
	}

	compileOptions {
		sourceCompatibility = JavaVersion.VERSION_17
		targetCompatibility = JavaVersion.VERSION_17
	}
}

dependencies {
	implementation("org.godotengine:godot:4.7.2.stable")
	implementation("androidx.annotation:annotation:1.8.1")
	implementation("androidx.core:core:1.13.1")
}
