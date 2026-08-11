// SPDX-License-Identifier: Apache-2.0
package com.dragonq6a.wifiadapter;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.widget.Toast;

/**
 * "Activate" action handler. Forwards the dongle interface name to
 * {@link AdapterMonitorService}, which performs the STA switch on its own worker
 * thread (set wifi.interface + cycle Wi-Fi via WifiManager).
 *
 * NOTE: the switch is done IN-PROCESS, not via an init service. The app runs as
 * android.uid.system and is platform-signed, and this device is globally permissive,
 * so it can set wifi.interface and toggle Wi-Fi directly. The earlier ctl.start
 * approach failed: init refuses to start a /system/bin service with no SELinux
 * domain transition ("incorrect label or no domain transition") even in permissive
 * mode, and the failed ctl.start set crashed this receiver.
 */
public class ActivateReceiver extends BroadcastReceiver {
    static final String ACTION_ACTIVATE = "com.dragonq6a.wifiadapter.ACTIVATE";
    static final String EXTRA_IFACE = "iface";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (!ACTION_ACTIVATE.equals(intent.getAction())) return;
        String iface = intent.getStringExtra(EXTRA_IFACE);
        if (iface == null || iface.isEmpty()) iface = "wlan1";

        Intent svc = new Intent(context, AdapterMonitorService.class);
        svc.setAction(AdapterMonitorService.ACTION_SWITCH);
        svc.putExtra(EXTRA_IFACE, iface);
        context.startService(svc);

        Toast.makeText(context,
                context.getString(R.string.toast_activating, iface),
                Toast.LENGTH_LONG).show();
    }
}
