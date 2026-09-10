package com.micjason.xiuxian.updater;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import androidx.annotation.NonNull;
import androidx.core.content.FileProvider;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import java.io.File;
import java.util.List;

public final class XiuxianUpdaterPlugin extends GodotPlugin {
	public XiuxianUpdaterPlugin(Godot godot) {
		super(godot);
	}

	@NonNull
	@Override
	public String getPluginName() {
		return BuildConfig.GODOT_PLUGIN_NAME;
	}

	@UsedByGodot
	public String getVersionName() {
		PackageInfo info = getPackageInfo();
		return info == null || info.versionName == null ? "0.0.0" : info.versionName;
	}

	@UsedByGodot
	public long getVersionCode() {
		PackageInfo info = getPackageInfo();
		if (info == null) {
			return 0L;
		}
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
			return info.getLongVersionCode();
		}
		return info.versionCode;
	}

	@UsedByGodot
	public boolean canRequestPackageInstalls() {
		Activity activity = getActivity();
		if (activity == null) {
			return false;
		}
		return Build.VERSION.SDK_INT < Build.VERSION_CODES.O
			|| activity.getPackageManager().canRequestPackageInstalls();
	}

	@UsedByGodot
	public void requestInstallPermission() {
		Activity activity = getActivity();
		if (activity == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
			return;
		}
		activity.runOnUiThread(() -> {
			Intent intent = new Intent(
				Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
				Uri.parse("package:" + activity.getPackageName())
			);
			activity.startActivity(intent);
		});
	}

	@UsedByGodot
	public boolean installApk(String path) {
		Activity activity = getActivity();
		File apk = new File(path);
		if (activity == null || !apk.isFile() || !canRequestPackageInstalls()) {
			return false;
		}
		if (apkVersionCode(path) <= getVersionCode()) {
			return false;
		}

		activity.runOnUiThread(() -> {
			Uri uri = FileProvider.getUriForFile(
				activity,
				activity.getPackageName() + ".fileprovider",
				apk
			);
			Intent intent = new Intent(Intent.ACTION_VIEW);
			intent.setDataAndType(uri, "application/vnd.android.package-archive");
			intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
			grantInstallUri(activity, intent, uri);
			activity.startActivity(intent);
		});
		return true;
	}

	private long apkVersionCode(String path) {
		Activity activity = getActivity();
		if (activity == null) {
			return 0L;
		}
		PackageInfo info = activity.getPackageManager().getPackageArchiveInfo(path, 0);
		if (info == null) {
			return 0L;
		}
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
			return info.getLongVersionCode();
		}
		return info.versionCode;
	}

	private void grantInstallUri(Activity activity, Intent intent, Uri uri) {
		PackageManager manager = activity.getPackageManager();
		List<ResolveInfo> receivers = manager.queryIntentActivities(
			intent,
			PackageManager.MATCH_DEFAULT_ONLY
		);
		for (ResolveInfo receiver : receivers) {
			if (receiver.activityInfo == null) {
				continue;
			}
			activity.grantUriPermission(
				receiver.activityInfo.packageName,
				uri,
				Intent.FLAG_GRANT_READ_URI_PERMISSION
			);
		}
	}

	private PackageInfo getPackageInfo() {
		Activity activity = getActivity();
		if (activity == null) {
			return null;
		}
		try {
			return activity.getPackageManager().getPackageInfo(activity.getPackageName(), 0);
		} catch (Exception ignored) {
			return null;
		}
	}
}
