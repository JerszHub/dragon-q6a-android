// SPDX-License-Identifier: Apache-2.0
package com.dragonq6a.wifiadapter;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Starts the adapter-monitor service once the framework is up. */
public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) {
            context.startService(new Intent(context, AdapterMonitorService.class));
        }
    }
}
