package com.micjason.xiuxian.updater;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInstaller;
import android.os.Build;

public final class InstallStatusReceiver extends BroadcastReceiver {
	static final String ACTION = "com.micjason.xiuxian.INSTALL_STATUS";

	@Override
	public void onReceive(Context context, Intent intent) {
		if (context == null || intent == null) {
			return;
		}
		int status = intent.getIntExtra(
			PackageInstaller.EXTRA_STATUS,
			PackageInstaller.STATUS_FAILURE
		);
		if (status != PackageInstaller.STATUS_PENDING_USER_ACTION) {
			return;
		}

		Intent confirm = extraIntent(intent);
		if (confirm == null) {
			return;
		}
		confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
		context.startActivity(confirm);
	}

	private static Intent extraIntent(Intent intent) {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
			return intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent.class);
		}
		return intent.getParcelableExtra(Intent.EXTRA_INTENT);
	}
}
