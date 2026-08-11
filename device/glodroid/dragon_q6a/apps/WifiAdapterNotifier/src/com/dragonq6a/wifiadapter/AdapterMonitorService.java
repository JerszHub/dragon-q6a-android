// SPDX-License-Identifier: Apache-2.0
package com.dragonq6a.wifiadapter;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.net.wifi.WifiManager;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.SystemProperties;
import android.util.Log;

import java.io.File;
import java.util.HashSet;
import java.util.Set;

/**
 * Detects a USB Wi-Fi dongle and posts / clears a notification with an "Activate"
 * action. Runs in a persistent system process (no foreground-service notification).
 *
 * Detection is a POSITIVE allow-list of the dongle driver names we ship firmware for
 * (rtl8xxxu / rtw88_* / mt76* / brcmfmac). This is robust regardless of interface
 * index or plug order: the onboard AIC8800 reports driver "usb" (NOT "aic" as first
 * assumed) and never matches, while any real dongle does — whether present at boot or
 * hot-plugged. Notifies when a dongle iface appears, cancels when it goes; re-notifies
 * on re-insertion. The poll body is wrapped so one bad iteration can't kill monitoring.
 */
public class AdapterMonitorService extends Service {

    private static final String TAG = "WifiAdapterNotifier";
    private static final String CHANNEL_ID = "wifi_adapter";
    private static final int NOTIF_ID_BASE = 0x77A10000;
    private static final long POLL_MS = 3000;
    private static final long WIFI_CYCLE_MS = 2500;   // teardown gap before re-enable
    private static final String ONBOARD_IFACE = "wlan0";

    /** Perform the STA switch to the dongle handed over by ActivateReceiver. */
    static final String ACTION_SWITCH = "com.dragonq6a.wifiadapter.action.SWITCH";

    private HandlerThread mThread;
    private Handler mHandler;
    private final Set<String> mPresent = new HashSet<>(); // dongle ifaces currently notified
    private boolean mRevertPending = false;                // guards the one-shot STA revert

    @Override
    public void onCreate() {
        super.onCreate();
        NotificationManager nm = getSystemService(NotificationManager.class);
        NotificationChannel ch = new NotificationChannel(
                CHANNEL_ID, getString(R.string.channel_name),
                NotificationManager.IMPORTANCE_DEFAULT);
        ch.setDescription(getString(R.string.channel_desc));
        nm.createNotificationChannel(ch);

        mThread = new HandlerThread("wifiAdapterPoll");
        mThread.start();
        mHandler = new Handler(mThread.getLooper());
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && ACTION_SWITCH.equals(intent.getAction())) {
            final String iface = intent.getStringExtra(ActivateReceiver.EXTRA_IFACE);
            mHandler.post(new Runnable() {
                @Override public void run() { switchStaTo(iface); }
            });
            // Don't disturb the poll loop; it's already running (persistent process).
            return START_STICKY;
        }
        mHandler.removeCallbacks(mPoll);
        mHandler.post(mPoll);
        return START_STICKY;
    }

    /**
     * Point the Wi-Fi framework's STA at {@code iface} and cycle Wi-Fi so it rebinds.
     * Setting wifi.interface + toggling Wi-Fi is exactly what was validated live via
     * `setprop wifi.interface <x>; svc wifi disable/enable` — done here in-process
     * (WifiManager) to avoid the init-service/SELinux path. Runs on the poll thread.
     */
    private void switchStaTo(String iface) {
        if (iface == null || iface.isEmpty()) return;
        Log.i(TAG, "switching Wi-Fi STA to " + iface);
        SystemProperties.set("wifi.interface", iface);
        SystemProperties.set("sys.wifidongle.result", "switching STA to " + iface);
        cycleWifi();
        SystemProperties.set("sys.wifidongle.result", "done: STA -> " + iface);
    }

    /** Revert the STA to the onboard interface (wlan0) and cycle Wi-Fi. */
    private void revertStaToOnboard() {
        Log.i(TAG, "reverting Wi-Fi STA to " + ONBOARD_IFACE);
        SystemProperties.set("wifi.interface", ONBOARD_IFACE);
        cycleWifi();
        SystemProperties.set("sys.wifidongle.result", "reverted: STA -> " + ONBOARD_IFACE);
    }

    /** setWifiEnabled(false) -> gap -> setWifiEnabled(true), rebinding the STA iface. */
    private void cycleWifi() {
        WifiManager wm = getSystemService(WifiManager.class);
        if (wm == null) { Log.w(TAG, "no WifiManager"); return; }
        wm.setWifiEnabled(false);
        try { Thread.sleep(WIFI_CYCLE_MS); } catch (InterruptedException ignored) {}
        wm.setWifiEnabled(true);
    }

    private final Runnable mPoll = new Runnable() {
        @Override
        public void run() {
            try {
                Set<String> dongles = findDongleIfaces();
                for (String iface : dongles) {
                    if (!mPresent.contains(iface)) showNotification(iface);
                }
                for (String iface : new HashSet<>(mPresent)) {
                    if (!dongles.contains(iface)) cancelNotification(iface);
                }
                mPresent.clear();
                mPresent.addAll(dongles);
                maybeRevertStaleInterface();
            } catch (Throwable t) {
                // Never let a transient /sys race or notif error stop monitoring.
                Log.w(TAG, "poll iteration failed", t);
            } finally {
                mHandler.postDelayed(this, POLL_MS);
            }
        }
    };

    /** wlan* interfaces whose kernel driver is a known USB Wi-Fi dongle driver. */
    private Set<String> findDongleIfaces() {
        Set<String> out = new HashSet<>();
        File[] ifaces = new File("/sys/class/net").listFiles();
        if (ifaces == null) return out;
        for (File f : ifaces) {
            String name = f.getName();
            if (!name.startsWith("wlan")) continue;
            if (isDongleDriver(driverOf(name))) out.add(name);
        }
        return out;
    }

    /**
     * If "Activate" pointed wifi.interface at a dongle that has since been UNPLUGGED,
     * Wi-Fi is now bound to a gone interface and would stay dead until reboot. Trigger
     * the revert helper to put the STA back on the onboard wlan0. Guarded so it fires
     * once (the revert script sets wifi.interface=wlan0, clearing the condition).
     */
    private void maybeRevertStaleInterface() {
        String wi = SystemProperties.get("wifi.interface", ONBOARD_IFACE);
        boolean stale = wi.startsWith("wlan") && !wi.equals(ONBOARD_IFACE)
                && !new File("/sys/class/net/" + wi).exists();
        if (stale && !mRevertPending) {
            mRevertPending = true;
            Log.i(TAG, "activated dongle " + wi + " gone -> reverting STA to " + ONBOARD_IFACE);
            revertStaToOnboard();
        } else if (!stale) {
            mRevertPending = false;
        }
    }

    /** True for the USB dongle drivers we bundle firmware for; false for onboard/others. */
    private boolean isDongleDriver(String d) {
        if (d == null) return false;
        d = d.toLowerCase();
        return d.equals("rtl8xxxu")
                || d.startsWith("rtw88")     // rtw88_8821au / 8822bu / 8821cu / 8723du / 8812au
                || d.startsWith("rtl81") || d.startsWith("rtl87") || d.startsWith("rtl88")
                || d.startsWith("mt76")      // mt7601u / mt76x0u / mt76x2u / mt7663u
                || d.startsWith("mt79")      // mt7921u / mt7925u
                || d.startsWith("brcmfmac");
    }

    private String driverOf(String iface) {
        try {
            File link = new File("/sys/class/net/" + iface + "/device/driver");
            if (!link.exists()) return null;
            return link.getCanonicalFile().getName();
        } catch (Exception e) {
            return null;
        }
    }

    private int notifId(String iface) {
        return NOTIF_ID_BASE + (iface.hashCode() & 0xFFFF);
    }

    private void showNotification(String iface) {
        Intent activate = new Intent(this, ActivateReceiver.class);
        activate.setAction(ActivateReceiver.ACTION_ACTIVATE);
        activate.putExtra(ActivateReceiver.EXTRA_IFACE, iface);
        PendingIntent pi = PendingIntent.getBroadcast(this, iface.hashCode(), activate,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        Notification n = new Notification.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_wifi_adapter)
                .setContentTitle(getString(R.string.notif_title))
                .setContentText(getString(R.string.notif_text, iface))
                .setAutoCancel(false)
                .addAction(new Notification.Action.Builder(
                        null, getString(R.string.action_activate), pi).build())
                .build();

        getSystemService(NotificationManager.class).notify(notifId(iface), n);
    }

    private void cancelNotification(String iface) {
        getSystemService(NotificationManager.class).cancel(notifId(iface));
    }

    @Override
    public void onDestroy() {
        if (mThread != null) mThread.quitSafely();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
