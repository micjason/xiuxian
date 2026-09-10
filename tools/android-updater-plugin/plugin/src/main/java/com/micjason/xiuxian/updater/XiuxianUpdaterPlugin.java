package com.micjason.xiuxian.updater;

import android.app.Activity;
import android.app.PendingIntent;
import android.content.ClipData;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageInstaller;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import androidx.annotation.NonNull;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.List;

public final class XiuxianUpdaterPlugin extends GodotPlugin {
	private static final String[] INSTALLER_PACKAGES = {
		"com.android.packageinstaller",
		"com.google.android.packageinstaller",
		"com.oplus.packageinstaller",
		"com.coloros.packageinstaller",
		"com.samsung.android.packageinstaller",
		"com.miui.packageinstaller",
		"com.huawei.appmarket",
		"com.vivo.packageinstaller",
	};

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
		return versionCodeOf(getPackageInfo());
	}

	@UsedByGodot
	public long getApkVersionCode(String path) {
		return versionCodeOf(archiveInfo(path));
	}

	@UsedByGodot
	public String getApkVersionName(String path) {
		PackageInfo info = archiveInfo(path);
		return info == null || info.versionName == null ? "" : info.versionName;
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
		if (getApkVersionCode(path) <= getVersionCode()) {
			return false;
		}

		new Thread(() -> {
			try {
				commitInstallerSession(activity, apk);
			} catch (Exception ignored) {
				activity.runOnUiThread(() -> startFileProviderInstall(activity, apk));
			}
		}, "xiuxian-install").start();
		return true;
	}

	private void commitInstallerSession(Activity activity, File apk) throws IOException {
		PackageInstaller installer = activity.getPackageManager().getPackageInstaller();
		abandonOwnSessions(installer);

		PackageInstaller.SessionParams params = new PackageInstaller.SessionParams(
			PackageInstaller.SessionParams.MODE_FULL_INSTALL
		);
		params.setAppPackageName(activity.getPackageName());
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
			params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED);
		}

		int sessionId = installer.createSession(params);
		PackageInstaller.Session session = installer.openSession(sessionId);
		try {
			try (
				OutputStream out = session.openWrite("xiuxian.apk", 0, apk.length());
				InputStream in = new FileInputStream(apk)
			) {
				copyStream(in, out);
				session.fsync(out);
			}

			Intent broadcast = new Intent(activity, InstallStatusReceiver.class);
			broadcast.setAction(InstallStatusReceiver.ACTION);
			broadcast.setPackage(activity.getPackageName());
			int flags = PendingIntent.FLAG_UPDATE_CURRENT;
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
				flags |= PendingIntent.FLAG_MUTABLE;
			}
			PendingIntent pending = PendingIntent.getBroadcast(activity, sessionId, broadcast, flags);
			session.commit(pending.getIntentSender());
		} catch (Exception error) {
			try {
				session.abandon();
			} catch (Exception ignored) {
			}
			throw error instanceof IOException ? (IOException) error : new IOException(error);
		}
	}

	private void startFileProviderInstall(Activity activity, File apk) {
		try {
			File staged = copyToInstallCache(activity, apk);
			Uri uri = UpdateFileProvider.getUriForFile(
				activity,
				activity.getPackageName() + ".update.fileprovider",
				staged
			);
			Intent intent = new Intent(Intent.ACTION_INSTALL_PACKAGE);
			intent.setDataAndType(uri, "application/vnd.android.package-archive");
			intent.putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true);
			intent.putExtra(Intent.EXTRA_RETURN_RESULT, false);
			intent.setClipData(ClipData.newRawUri("xiuxian-update", uri));
			intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
			grantInstallUri(activity, intent, uri);
			if (intent.resolveActivity(activity.getPackageManager()) == null) {
				intent.setAction(Intent.ACTION_VIEW);
			}
			activity.startActivity(intent);
		} catch (Exception ignored) {
		}
	}

	private File copyToInstallCache(Activity activity, File apk) throws IOException {
		File directory = new File(activity.getCacheDir(), "updates");
		if (!directory.isDirectory() && !directory.mkdirs()) {
			throw new IOException("Unable to create update cache.");
		}
		File staged = new File(directory, "xiuxian-install.apk");
		try (
			InputStream in = new FileInputStream(apk);
			OutputStream out = new FileOutputStream(staged)
		) {
			copyStream(in, out);
		}
		return staged;
	}

	private static void copyStream(InputStream in, OutputStream out) throws IOException {
		byte[] buffer = new byte[64 * 1024];
		int read;
		while ((read = in.read(buffer)) > 0) {
			out.write(buffer, 0, read);
		}
	}

	private static void abandonOwnSessions(PackageInstaller installer) {
		for (PackageInstaller.SessionInfo info : installer.getMySessions()) {
			try {
				installer.abandonSession(info.getSessionId());
			} catch (Exception ignored) {
			}
		}
	}

	private void grantInstallUri(Activity activity, Intent intent, Uri uri) {
		PackageManager manager = activity.getPackageManager();
		int flags = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
			? PackageManager.MATCH_DEFAULT_ONLY | PackageManager.MATCH_ALL
			: PackageManager.MATCH_DEFAULT_ONLY;
		List<ResolveInfo> receivers = manager.queryIntentActivities(intent, flags);
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
		for (String packageName : INSTALLER_PACKAGES) {
			activity.grantUriPermission(
				packageName,
				uri,
				Intent.FLAG_GRANT_READ_URI_PERMISSION
			);
		}
	}

	private PackageInfo archiveInfo(String path) {
		Activity activity = getActivity();
		if (activity == null || path == null || path.isEmpty()) {
			return null;
		}
		return activity.getPackageManager().getPackageArchiveInfo(path, 0);
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

	private static long versionCodeOf(PackageInfo info) {
		if (info == null) {
			return 0L;
		}
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
			return info.getLongVersionCode();
		}
		return info.versionCode;
	}
}
