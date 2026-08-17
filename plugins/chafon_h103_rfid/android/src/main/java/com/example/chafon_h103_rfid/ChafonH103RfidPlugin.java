package com.example.chafon_h103_rfid;

import android.bluetooth.BluetoothDevice;
import android.bluetooth.le.ScanResult;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.cf.beans.AllParamBean;
import com.cf.beans.BatteryCapacityBean;
import com.cf.beans.CmdData;
import com.cf.beans.KeyStateBean;
import com.cf.beans.TagInfoBean;
import com.cf.beans.TagOperationBean;
import com.cf.ble.interfaces.IBtScanCallback;
import com.cf.ble.interfaces.IConnectDoneCallback;
import com.cf.ble.interfaces.IOnNotifyCallback;
import com.cf.zsdk.BleCore;
import com.cf.zsdk.CfSdk;
import com.cf.zsdk.SdkC;
import com.cf.zsdk.cmd.CmdBuilder;
import com.cf.zsdk.cmd.CmdType;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class ChafonH103RfidPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private MethodChannel channel;
    private Context context;
    private BleCore bleCore;
    private final Map<String, BluetoothDevice> discoveredDevices = new HashMap<>();
    private IBtScanCallback scanCallback;
    private boolean isScanning = false;

    private MethodChannel.Result pendingGetConfigResult;
    private MethodChannel.Result pendingSaveFlashResult;

    // Exact EPC radar mode
    private String radarEpc = null;
    private boolean radarActive = false;

    // Masked radar mode (software-side)
    private boolean radarUseMask = false;
    private int radarMaskStartAddress = 0; // byte offset inside EPC
    private int radarMaskLengthBytes = 0;  // byte count
    private String radarMaskHex = null;    // normalized uppercase HEX

    private final Handler batteryTimeoutHandler = new Handler(Looper.getMainLooper());
    private Runnable batteryTimeoutRunnable;

    private final Handler flashTimeoutHandler = new Handler(Looper.getMainLooper());
    private Runnable flashTimeoutRunnable;

    private AllParamBean latestAllParam = null;

    // BLE hazır/notify aktiv flaqı və əməliyyat kilidi
    private volatile boolean bleReady = false;
    private final AtomicBoolean opInProgress = new AtomicBoolean(false);

    // Inventory vəziyyətini izləmək üçün flaq
    private volatile boolean inventoryRunning = false;

    // Güc aralığı
    private static final int POWER_MIN = 5;
    private static final int POWER_MAX = 33; // slider 33-ə qədər

    // Read modes
    private static final byte READ_MODE_RFID = 0x00;
    private static final byte READ_MODE_BARCODE = 0x01;
    private static final long BARCODE_FLUSH_DELAY_MS = 120L;

    private volatile byte currentReadMode = READ_MODE_RFID;
    private volatile boolean barcodeTriggerActive = false;

    private final Handler barcodeBufferHandler = new Handler(Looper.getMainLooper());
    private final Object barcodeBufferLock = new Object();
    private final StringBuilder barcodeBuffer = new StringBuilder();
    private Runnable barcodeFlushRunnable;

    private static final UUID SERVICE_UUID = UUID.fromString("0000ffe0-0000-1000-8000-00805f9b34fb");
    private static final UUID WRITE_UUID   = UUID.fromString("0000ffe3-0000-1000-8000-00805f9b34fb");
    private static final UUID NOTIFY_UUID  = UUID.fromString("0000ffe4-0000-1000-8000-00805f9b34fb");

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        context = flutterPluginBinding.getApplicationContext();
        channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "chafon_h103_rfid");
        channel.setMethodCallHandler(this);

        CfSdk.load();
        bleCore = (BleCore) CfSdk.get(SdkC.BLE);
        bleCore.init(context);
        bleCore.setOnNotifyCallback(universalNotifyCallback);
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        try {
            Log.d("CHAFON_PLUGIN", "📞 Method çağırıldı: " + call.method);
            switch (call.method) {
                case "getPlatformVersion":
                    result.success("Android " + android.os.Build.VERSION.RELEASE);
                    break;

                case "getBatteryLevel":
                    getBatteryLevel(result);
                    break;

                case "startScan":
                    startScan(result);
                    break;

                case "stopScan":
                    stopScan(result);
                    break;

                case "connect": {
                    String address = call.argument("address");
                    if (address != null && !address.isEmpty()) {
                        connect(address, result);
                    } else {
                        result.error("INVALID_ARGUMENT", "Address is null or empty", null);
                    }
                    break;
                }

                case "isConnected":
                    result.success(bleCore != null && bleCore.isConnect());
                    break;

                case "disconnect":
                    disconnect(result);
                    break;

                case "getAllDeviceConfig":
                    getAllDeviceConfig(result);
                    break;

                case "sendAndSaveAllParams": {
                    Integer power   = call.argument("power");
                    Integer region  = call.argument("region");
                    Integer qValue  = call.argument("qValue");
                    Integer session = call.argument("session");

                    int pwr = power   != null ? power   : 17;
                    int reg = region  != null ? region  : 2;
                    int q   = qValue  != null ? qValue  : 4;
                    int ses = session != null ? session : 0;
                    sendAndSaveAllParams(pwr, reg, q, ses, result);
                    break;
                }

                case "setOnlyOutputPower": {
                    Integer power = call.argument("power");
                    Boolean saveToFlash = call.argument("saveToFlash"); // default true
                    Boolean resumeInventory = call.argument("resumeInventory"); // default false
                    Integer region = call.argument("region");

                    int pwr = power != null ? power : 17;
                    boolean save = (saveToFlash == null) ? true : saveToFlash;
                    boolean resume = (resumeInventory == null) ? false : resumeInventory;
                    int reg = (region == null) ? -1 : region;

                    setOnlyOutputPower(pwr, save, resume, reg, result);
                    break;
                }

                case "startInventory":
                    startInventory(result);
                    break;

                case "stopInventory":
                    stopInventory(result);
                    break;

                case "readSingleTag": {
                    Integer memoryBank = call.argument("memoryBank");
                    if (memoryBank == null) {
                        result.error("INVALID_ARGUMENT", "Missing 'memoryBank'", null);
                        return;
                    }
                    readTagByMemoryBank(memoryBank.byteValue(), result);
                    break;
                }

                case "startRadarTracking": {
                    String radarEpcValue = call.argument("epc");
                    if (radarEpcValue == null || radarEpcValue.isEmpty()) {
                        result.error("INVALID_ARGUMENT", "EPC boş ola bilməz", null);
                    } else {
                        startRadarTracking(radarEpcValue, result);
                    }
                    break;
                }

                case "startRadarMasked": {
                    Integer maskStartAddress = call.argument("maskStartAddress");
                    Integer maskLength = call.argument("maskLength");
                    String mask = call.argument("mask");

                    if (maskStartAddress == null) {
                        result.error("INVALID_ARGUMENT", "Missing 'maskStartAddress'", null);
                        return;
                    }
                    if (maskLength == null) {
                        result.error("INVALID_ARGUMENT", "Missing 'maskLength'", null);
                        return;
                    }
                    if (mask == null) {
                        result.error("INVALID_ARGUMENT", "Missing 'mask'", null);
                        return;
                    }

                    startRadarMasked(maskStartAddress, maskLength, mask, result);
                    break;
                }

                case "stopRadarTracking":
                    stopRadarTracking(result);
                    break;

                case "getReadMode":
                    result.success(currentReadMode == READ_MODE_BARCODE ? "barcode" : "rfid");
                    break;

                case "setReadMode": {
                    String mode = call.argument("mode");
                    if ("barcode".equalsIgnoreCase(mode)) {
                        enableBarcodeMode(result);
                    } else if ("rfid".equalsIgnoreCase(mode)) {
                        enableRfidMode(result);
                    } else {
                        result.error("INVALID_ARGUMENT", "mode must be 'rfid' or 'barcode'", null);
                    }
                    break;
                }

                case "startBarcodeScan":
                    startBarcodeScan(result);
                    break;

                case "stopBarcodeScan":
                    stopBarcodeScan(result);
                    break;

                default:
                    result.error(
                            "UNSUPPORTED_METHOD",
                            "Method " + call.method + " not supported",
                            Arrays.asList(
                                    "startScan",
                                    "stopScan",
                                    "connect",
                                    "disconnect",
                                    "isConnected",
                                    "getBatteryLevel",
                                    "getAllDeviceConfig",
                                    "setOnlyOutputPower",
                                    "sendAndSaveAllParams",
                                    "startInventory",
                                    "stopInventory",
                                    "readSingleTag",
                                    "startRadarTracking",
                                    "startRadarMasked",
                                    "stopRadarTracking",
                                    "getReadMode",
                                    "setReadMode",
                                    "startBarcodeScan",
                                    "stopBarcodeScan"
                            )
                    );
            }
        } catch (Exception e) {
            result.error("UNEXPECTED_ERROR", e.getMessage(), null);
        }
    }

    // ==== NOTIFY CALLBACK ====
    private final IOnNotifyCallback universalNotifyCallback = new IOnNotifyCallback() {
        @Override
        public void onNotify(int cmdType, CmdData cmdData) {
            try {
                Object obj = cmdData.getData();

                switch (cmdType) {
                    case CmdType.TYPE_GET_BATTERY_CAPACITY: {
                        Log.d("CHAFON_PLUGIN", "📩 TYPE_BATTERY cavabı gəldi");
                        if (obj instanceof BatteryCapacityBean) {
                            int battery = ((BatteryCapacityBean) obj).mBatteryCapacity;

                            if (batteryTimeoutRunnable != null) {
                                batteryTimeoutHandler.removeCallbacks(batteryTimeoutRunnable);
                                batteryTimeoutRunnable = null;
                            }

                            Map<String, Object> batteryMap = new HashMap<>();
                            batteryMap.put("level", battery);

                            new Handler(Looper.getMainLooper()).post(() -> {
                                channel.invokeMethod("onBatteryLevel", batteryMap);
                            });
                        }
                        break;
                    }

                    case CmdType.TYPE_OUT_MODE:
                        Log.d("CHAFON_PLUGIN", "📤 Output mode dəyişdi");
                        break;

                    case CmdType.TYPE_KEY_STATE: {
                        Log.d("CHAFON_PLUGIN", "🔘 Düymə statusu gəldi");

                        if (obj instanceof KeyStateBean) {
                            KeyStateBean keyStateBean = (KeyStateBean) obj;
                            barcodeTriggerActive = keyStateBean.mKeyState == 0x01;

                            Map<String, Object> keyMap = new HashMap<>();
                            keyMap.put("state", barcodeTriggerActive ? "start" : "finish");
                            keyMap.put("timestamp", System.currentTimeMillis());

                            new Handler(Looper.getMainLooper()).post(() -> {
                                channel.invokeMethod("onKeyState", keyMap);
                            });
                        }
                        break;
                    }

                    case CmdType.TYPE_GET_DEVICE_INFO:
                        Log.d("CHAFON_PLUGIN", "📡 Cihaz məlumatı gəldi");
                        break;

                    case CmdType.TYPE_GET_ALL_PARAM: {
                        if (obj instanceof AllParamBean) {
                            AllParamBean param = (AllParamBean) obj;
                            latestAllParam = param;

                            if (pendingGetConfigResult != null) {
                                Map<String, Object> config = new HashMap<>();
                                config.put("power",   (int) param.mRfidPower);
                                config.put("region",  (int) param.mRfidFreq.mREGION);
                                config.put("qValue",  (int) param.mQValue);
                                config.put("session", (int) param.mSession);

                                MethodChannel.Result callback = pendingGetConfigResult;
                                pendingGetConfigResult = null;
                                callback.success(config);
                            }
                        }
                        break;
                    }

                    case CmdType.TYPE_SET_ALL_PARAM:
                        Log.d("CHAFON_PLUGIN", "✅ Parametrlər RAM-a yazıldı (notify)");
                        break;

                    case CmdType.TYPE_INVENTORY: {
                        if (obj instanceof TagInfoBean) {
                            TagInfoBean tagInfoBean = (TagInfoBean) obj;

                            // Alineado con ScanFragment:
                            // en modo barcode, el SDK entrega el valor en TagInfoBean.mEPCNum
                            if (currentReadMode == READ_MODE_BARCODE) {
                                byte[] epcNum = tagInfoBean.mEPCNum;
                                if (epcNum != null && epcNum.length > 0) {
                                    String scanData = new String(epcNum)
                                            .replace("\u0000", "")
                                            .trim();

                                    if (!scanData.isEmpty()) {
                                        Map<String, Object> barcodeMap = new HashMap<>();
                                        barcodeMap.put("value", scanData);
                                        barcodeMap.put("timestamp", System.currentTimeMillis());

                                        new Handler(Looper.getMainLooper()).post(() -> {
                                            channel.invokeMethod("onBarcodeRead", barcodeMap);
                                        });
                                    }
                                }
                            } else {
                                handleInventoryTag(tagInfoBean);
                            }
                        }
                        break;
                    }

                    case CmdType.TYPE_READ_TAG: {
                        if (obj instanceof TagOperationBean) {
                            TagOperationBean tagOp = (TagOperationBean) obj;

                            int status = tagOp.mTagStatus;
                            Log.d("CHAFON_PLUGIN", "📛 TagOperationBean status: " + status);

                            String epc = bytesToHexString(tagOp.mEPCNum);
                            String data = bytesToHexString(tagOp.mData);
                            if (epc == null) epc = "";
                            if (data == null) data = "";

                            if (!epc.trim().isEmpty() || !data.trim().isEmpty()) {
                                Map<String, Object> tagMap = new HashMap<>();
                                tagMap.put("epc", epc.isEmpty() ? "<boş>" : epc);
                                tagMap.put("data", data);
                                tagMap.put("status", status);
                                tagMap.put("timestamp", System.currentTimeMillis());

                                new Handler(Looper.getMainLooper()).post(() -> {
                                    channel.invokeMethod("onTagReadSingle", tagMap);
                                });
                            } else {
                                Log.w("CHAFON_PLUGIN", "❌ READ_TAG cavabı keçərsizdir – nə EPC, nə də DATA var");
                            }
                        }
                        break;
                    }

                    default: {
                        Object any = cmdData.getData();
                        if (any instanceof TagInfoBean) {
                            if (currentReadMode == READ_MODE_BARCODE) {
                                TagInfoBean tagInfoBean = (TagInfoBean) any;
                                byte[] epcNum = tagInfoBean.mEPCNum;
                                if (epcNum != null && epcNum.length > 0) {
                                    String scanData = new String(epcNum)
                                            .replace("\u0000", "")
                                            .trim();

                                    if (!scanData.isEmpty()) {
                                        Map<String, Object> barcodeMap = new HashMap<>();
                                        barcodeMap.put("value", scanData);
                                        barcodeMap.put("timestamp", System.currentTimeMillis());

                                        new Handler(Looper.getMainLooper()).post(() -> {
                                            channel.invokeMethod("onBarcodeRead", barcodeMap);
                                        });
                                    }
                                }
                            } else {
                                handleInventoryTag((TagInfoBean) any);
                            }
                        } else {
                            Log.d("CHAFON_PLUGIN", "⚠️ Fallback: naməlum cmdType=" + cmdType + " obj=" + any);
                        }
                        break;
                    }
                }
            } catch (Exception e) {
                Log.e("NOTIFY_ERROR", "Callback processing error", e);
                Map<String, Object> errorMap = new HashMap<>();
                errorMap.put("error", e.getMessage());
                channel.invokeMethod("onReadError", errorMap);
            }
        }

        @Override
        public void onNotify(byte[] bytes) {
            if (bytes == null || bytes.length == 0) return;

            // Alineado con ScanFragment:
            // NO intentar decodificar barcode desde bytes crudos.
            // El barcode válido debe venir por onNotify(int, CmdData) -> TYPE_INVENTORY -> TagInfoBean.mEPCNum
            if (!looksLikeSdkFrame(bytes)) {
                Log.d("CHAFON_PLUGIN", "ℹ️ Raw notify ignorado: " + bytesToHexString(bytes));
                return;
            }

            if (bytes.length < 5) return;

            int cmd = bytes[3] & 0xFF;   // CMD
            int len = bytes[4] & 0xFF;   // LEN
            Log.d("CHAFON_PLUGIN", "🔍 CMD Header: " + cmd);

            // FLASH ack (0x79)
            if (cmd == 0x79) {
                Log.d("CHAFON_PLUGIN", "💾 FLASH əmri uğurla təsdiqləndi");

                if (flashTimeoutRunnable != null) {
                    flashTimeoutHandler.removeCallbacks(flashTimeoutRunnable);
                    flashTimeoutRunnable = null;
                }
                if (pendingSaveFlashResult != null) {
                    pendingSaveFlashResult.success("flash_saved");
                    pendingSaveFlashResult = null;
                }
                return;
            }

            // START INVENTORY ack (0x01, len=0x01, status byte)
            if (cmd == 0x01 && len == 0x01 && bytes.length >= 6) {
                int status = bytes[5] & 0xFF;
                if (status == 0x00 || status == 0x12 || status == 0x02) {
                    Log.d("CHAFON_PLUGIN", "✅ Inventory START ack (status=0x" + Integer.toHexString(status) + ")");
                    inventoryRunning = true;
                } else {
                    Log.w("CHAFON_PLUGIN", "❌ Inventory START ack status=0x" + Integer.toHexString(status));
                }
                return;
            }

            // STOP INVENTORY ack (0x02, len=0x01, status byte)
            if (cmd == 0x02 && len == 0x01 && bytes.length >= 6) {
                int status = bytes[5] & 0xFF;
                Log.d("CHAFON_PLUGIN", "↩️ STOP ack status=0x" + Integer.toHexString(status));
                inventoryRunning = false;
                return;
            }

            // En algunos firmwares, si el barcode viene con framing no documentado,
            // aquí podrías loguear bytesToHexString(bytes) para ajustar el parser.
        }
    };

    // ==== BLE əmrləri ====

    private void getBatteryLevel(MethodChannel.Result result) {
        if (bleCore == null || !bleCore.isConnect()) {
            result.error("DISCONNECTED", "Device not connected", null);
            return;
        }

        byte[] cmd = CmdBuilder.buildGetBatteryCapacityCmd();
        boolean sent = writeWithRetry(SERVICE_UUID, WRITE_UUID, cmd);

        if (sent) {
            Log.d("CHAFON_PLUGIN", "🔋 Battery səviyyə əmri göndərildi.");
            result.success("battery_request_sent");

            batteryTimeoutRunnable = () -> {
                Log.w("CHAFON_PLUGIN", "⏰ Battery cavabı gəlmədi (timeout)");
                channel.invokeMethod("onBatteryTimeout", null);
            };
            batteryTimeoutHandler.postDelayed(batteryTimeoutRunnable, 5000);

        } else {
            result.error("BATTERY_FAILED", "Unable to send battery command", null);
        }
    }

    private void startScan(MethodChannel.Result result) {
        Log.d("CHAFON_PLUGIN", "▶️ startScan metodu çağırıldı");

        if (isScanning) {
            Log.d("CHAFON_PLUGIN", "⚠️ Skan onsuz da davam edir");
            result.success("skan_onsuzda_davam_edir");
            return;
        }

        try {
            scanCallback = new IBtScanCallback() {
                @Override
                public void onBtScanResult(ScanResult pResult) {
                    BluetoothDevice device = pResult.getDevice();
                    if (device != null && device.getAddress() != null) {
                        if (!discoveredDevices.containsKey(device.getAddress())) {
                            discoveredDevices.put(device.getAddress(), device);
                            Map<String, Object> deviceInfo = new HashMap<>();
                            deviceInfo.put("name", device.getName() != null ? device.getName() : "Naməlum");
                            deviceInfo.put("address", device.getAddress());
                            deviceInfo.put("rssi", pResult.getRssi());

                            new Handler(Looper.getMainLooper()).post(() -> {
                                channel.invokeMethod("onDeviceFound", deviceInfo);
                            });
                        }
                    }
                }

                @Override
                public void onBtScanFail(int pErrorCode) {
                    Log.e("CHAFON_PLUGIN", "❌ Skan uğursuz oldu. Kod: " + pErrorCode);
                    new Handler(Looper.getMainLooper()).post(() -> {
                        channel.invokeMethod("onScanError", "Skan xətası: " + pErrorCode);
                    });
                }
            };

            bleCore.startScan(scanCallback);
            isScanning = true;
            Log.d("CHAFON_PLUGIN", "🚀 Skan başlatıldı!");
            result.success("skan_basladildi");
        } catch (Exception e) {
            Log.e("CHAFON_PLUGIN", "🔥 startScan xətası: " + e.getMessage());
            result.error("SCAN_ERROR", "Skan başladılmadı: " + e.getMessage(), null);
        }
    }

    private void stopScan(@Nullable MethodChannel.Result result) {
        if (!isScanning) {
            if (result != null) result.success("skan_onsuzda_dayandirilib");
            return;
        }

        try {
            bleCore.stopScan();
            isScanning = false;
            if (result != null) result.success("skan_dayandirildi");
        } catch (Exception e) {
            if (result != null) {
                result.error("STOP_SCAN_ERROR", "Skan dayandırılmadı: " + e.getMessage(), null);
            }
        }
    }

    private void connect(String address, MethodChannel.Result result) {
        if (isScanning) {
            stopScan(null);
        }

        BluetoothDevice device = discoveredDevices.get(address);
        if (device == null) {
            result.error("DEVICE_NOT_FOUND", "Device not found: " + address, null);
            return;
        }

        bleCore.setOnNotifyCallback(universalNotifyCallback);

        bleCore.setIConnectDoneCallback(new IConnectDoneCallback() {
            @Override
            public void onConnectDone(boolean success) {
                if (success) {
                    bleReady = false;
                    boolean notifySet = bleCore.setNotifyState(SERVICE_UUID, NOTIFY_UUID, true);
                    if (notifySet) {
                        new Handler(Looper.getMainLooper()).postDelayed(() -> {
                            bleReady = true;
                            configureAfterConnection(result);
                        }, 200);
                    } else {
                        result.error("NOTIFY_FAILED", "Failed to enable notifications", null);
                    }
                } else {
                    result.error("CONNECTION_FAILED", "Connection failed", null);
                }
            }
        });

        try {
            bleCore.connectDevice(device, context, true);
        } catch (Exception e) {
            result.error("CONNECTION_EXCEPTION", "Connection error: " + e.getMessage(), null);
        }
    }

    private void configureAfterConnection(MethodChannel.Result result) {
        try {
            bleReady = true;

            // Asegurar salida BLE transparente y no HID
//            writeWithRetry(SERVICE_UUID, WRITE_UUID, CmdBuilder.buildSetOutputModeCmd((byte) 0x01));
//            try { Thread.sleep(80); } catch (InterruptedException ignored) {}

            // Arrancar por defecto en modo RFID para mantener compatibilidad
            writeWithRetry(SERVICE_UUID, WRITE_UUID, CmdBuilder.buildSetReadModeCmd(READ_MODE_RFID, new byte[7]));
            currentReadMode = READ_MODE_RFID;
            barcodeTriggerActive = false;
            clearBarcodeBuffer();
            try { Thread.sleep(80); } catch (InterruptedException ignored) {}

            byte[] cmd = CmdBuilder.buildGetAllParamCmd();
            writeWithRetry(SERVICE_UUID, WRITE_UUID, cmd);

            result.success(true);
        } catch (Exception e) {
            result.error("CONFIGURATION_FAILED", "Config error: " + e.getMessage(), null);
        }
    }

    private void disconnect(MethodChannel.Result result) {
        try {
            bleCore.setIConnectDoneCallback(null);
            bleCore.setOnNotifyCallback(null);
            bleCore.disconnectedDevice();

            bleReady = false;
            latestAllParam = null;
            inventoryRunning = false;
            clearRadarState();

            currentReadMode = READ_MODE_RFID;
            barcodeTriggerActive = false;
            clearBarcodeBuffer();

            result.success(true);

            new Handler(Looper.getMainLooper()).post(() -> {
                channel.invokeMethod("onDisconnected", null);
            });
        } catch (Exception e) {
            result.error("DISCONNECT_FAILED", "Bağlantı kəsilmədi: " + e.getMessage(), null);
        }
    }

    private void getAllDeviceConfig(MethodChannel.Result result) {
        try {
            if (!waitBleReady(1000)) {
                result.error("BLE_NOT_READY", "Notify hazır deyil", null);
                return;
            }
            byte[] cmd = CmdBuilder.buildGetAllParamCmd();
            boolean sent = writeWithRetry(SERVICE_UUID, WRITE_UUID, cmd);

            if (sent) {
                pendingGetConfigResult = result;
            } else {
                result.error("READ_CONFIG_FAILED", "BLE oxuma əmri göndərilmədi", null);
            }
        } catch (Exception e) {
            result.error("READ_CONFIG_EXCEPTION", "Xəta: " + e.getMessage(), null);
        }
    }

    private void saveParamsToFlash(MethodChannel.Result result) {
        try {
            Log.d("CHAFON_PLUGIN", "💾 FLASH yaddaşa yazma əmri göndərilir...");

            pendingSaveFlashResult = result;

            byte[] cmd = new byte[]{ (byte) 0xCF, (byte) 0xFF, 0x00, (byte) 0x79, 0x00, 0x00, 0x00 };
            int crc = calculateCRC16(cmd, 5);
            cmd[5] = (byte) ((crc >> 8) & 0xFF);
            cmd[6] = (byte) (crc & 0xFF);

            boolean sent = writeWithRetry(SERVICE_UUID, WRITE_UUID, cmd);
            if (!sent) {
                pendingSaveFlashResult = null;
                result.error("FLASH_WRITE_FAILED", "FLASH əmrini göndərmək alınmadı", null);
                return;
            }

            flashTimeoutRunnable = () -> {
                if (pendingSaveFlashResult != null) {
                    MethodChannel.Result r = pendingSaveFlashResult;
                    pendingSaveFlashResult = null;
                    r.error("FLASH_TIMEOUT", "FLASH cavabı gəlmədi", null);
                }
            };
            flashTimeoutHandler.postDelayed(flashTimeoutRunnable, 2000);

        } catch (Exception e) {
            result.error("FLASH_EXCEPTION", "Xəta baş verdi: " + e.getMessage(), null);
        }
    }

    private void setOnlyOutputPower(int power,
                                    boolean saveToFlash,
                                    boolean resumeInventory,
                                    int regionOrMinus1,
                                    MethodChannel.Result result) {
        Log.d("CHAFON_PLUGIN", "⚙️ setOnlyOutputPower(power=" + power + ", save=" + saveToFlash +
                ", resume=" + resumeInventory + ", region=" + regionOrMinus1 + ")");

        if (latestAllParam == null) {
            result.error("NO_BASE_CONFIG", "Əvvəlcə getAllDeviceConfig çağırılmalıdır (baseline yoxdur)", null);
            return;
        }

        boolean wasRunning = inventoryRunning;

        try {
            if (!waitBleReady(1000) || bleCore == null || !bleCore.isConnect()) {
                result.error("BLE_NOT_READY", "Cihaz qoşulu deyil və ya notify hazır deyil", null);
                return;
            }

            if (wasRunning) {
                internalStopInventory();
                try { Thread.sleep(150); } catch (InterruptedException ignored) {}
            }

            int p = Math.max(POWER_MIN, Math.min(POWER_MAX, power));
            latestAllParam.mRfidPower = (byte) p;
            latestAllParam.mRfidFreq  = buildFreqByRegion(2); // EU/ETSI sabit 2

            byte[] cmd = CmdBuilder.buildSetAllParamCmd(latestAllParam);
            boolean sent = writeWithRetry(SERVICE_UUID, WRITE_UUID, cmd);
            if (!sent) {
                if (resumeInventory && wasRunning) internalStartInventory();
                result.error("WRITE_FAILED", "Parametrlər RAM-a yazılmadı", null);
                return;
            }

            if (saveToFlash) {
                saveParamsToFlash(new MethodChannel.Result() {
                    @Override public void success(Object res) {
                        if (resumeInventory && wasRunning) internalStartInventory();
                        result.success(res);
                    }
                    @Override public void error(String code, String msg, Object details) {
                        if (resumeInventory && wasRunning) internalStartInventory();
                        result.error(code, msg, details);
                    }
                    @Override public void notImplemented() {
                        if (resumeInventory && wasRunning) internalStartInventory();
                        result.notImplemented();
                    }
                });
            } else {
                if (resumeInventory && wasRunning) internalStartInventory();
                result.success("ok");
            }

        } catch (Exception e) {
            if (resumeInventory && wasRunning) internalStartInventory();
            result.error("SET_POWER_EXCEPTION", e.getMessage(), null);
        }
    }

    private void sendAndSaveAllParams(int power, int region, int qValue, int session, MethodChannel.Result result) {
        Log.d("CHAFON_PLUGIN", "📦 sendAndSaveAllParams(power=" + power + ", region=" + region + ", q=" + qValue + ", s=" + session + ")");

        if (!opInProgress.compareAndSet(false, true)) {
            result.error("BUSY", "Başqa parametrlər əməliyyatı gedir", null);
            return;
        }

        boolean wasRunning = inventoryRunning;

        try {
            if (!waitBleReady(1000) || bleCore == null || !bleCore.isConnect()) {
                opInProgress.set(false);
                result.error("BLE_NOT_READY", "Notify/CCCD hazır deyil və ya cihaz qoşulu deyil", null);
                return;
            }

            if (wasRunning) {
                internalStopInventory();
                try { Thread.sleep(150); } catch (InterruptedException ignored) {}
            }

            if (latestAllParam == null) {
                opInProgress.set(false);
                result.error("NO_BASE_CONFIG", "Əvvəlcə getAllDeviceConfig çağırılmalıdır (baseline yoxdur)", null);
                return;
            }

            int p = Math.max(POWER_MIN, Math.min(POWER_MAX, power));
            latestAllParam.mRfidPower = (byte) p;
            latestAllParam.mQValue    = (byte) qValue;
            latestAllParam.mSession   = (byte) session;
            latestAllParam.mRfidFreq  = buildFreqByRegion(2); // region sabit EU

            byte[] cmd = CmdBuilder.buildSetAllParamCmd(latestAllParam);
            boolean sent = writeWithRetry(SERVICE_UUID, WRITE_UUID, cmd);
            if (!sent) {
                if (wasRunning) internalStartInventory();
                opInProgress.set(false);
                result.error("WRITE_FAILED", "Parametrlər RAM-a yazıla bilmədi", null);
                return;
            }

            saveParamsToFlash(new MethodChannel.Result() {
                @Override public void success(Object res) {
                    if (wasRunning) internalStartInventory();
                    opInProgress.set(false);
                    result.success(res);
                }
                @Override public void error(String code, String msg, Object details) {
                    if (wasRunning) internalStartInventory();
                    opInProgress.set(false);
                    result.error(code, msg, details);
                }
                @Override public void notImplemented() {
                    if (wasRunning) internalStartInventory();
                    opInProgress.set(false);
                    result.notImplemented();
                }
            });

        } catch (Exception e) {
            if (wasRunning) internalStartInventory();
            opInProgress.set(false);
            result.error("WRITE_EXCEPTION", "Xəta baş verdi: " + e.getMessage(), null);
        }
    }

    // ==== Helper-lər ====

    private boolean waitBleReady(long timeoutMs) {
        long end = System.currentTimeMillis() + timeoutMs;
        while (!bleReady && System.currentTimeMillis() < end) {
            try { Thread.sleep(50); } catch (InterruptedException ignored) {}
        }
        return bleReady;
    }

    private boolean writeWithRetry(UUID service, UUID write, byte[] data) {
        for (int i = 0; i < 3; i++) {
            boolean ok = bleCore.writeData(service, write, data);
            if (ok) return true;
            try { Thread.sleep(120L * (i + 1)); } catch (InterruptedException ignored) {}
        }
        return false;
    }

    private AllParamBean.RfidFreq buildFreqByRegion(int region) {
        AllParamBean.RfidFreq freq = new AllParamBean.RfidFreq();
        freq.mSTRATFREI = new byte[2];
        freq.mSTRATFRED = new byte[2];
        freq.mSTEPFRE   = new byte[2];

        if (region == 1) { // FCC
            freq.mREGION = 0x01;
            freq.mSTRATFREI[0] = 0x03; freq.mSTRATFREI[1] = (byte) 0x86;
            freq.mSTRATFRED[0] = 0x02; freq.mSTRATFRED[1] = (byte) 0xEE;
            freq.mSTEPFRE[0]   = 0x01; freq.mSTEPFRE[1]   = (byte) 0xF4;
            freq.mCN = 0x32;
        } else {           // ETSI (default)
            freq.mREGION = 0x03;
            freq.mSTRATFREI[0] = 0x03; freq.mSTRATFREI[1] = (byte) 0x61;
            freq.mSTRATFRED[0] = 0x00; freq.mSTRATFRED[1] = (byte) 0x64;
            freq.mSTEPFRE[0]   = 0x00; freq.mSTEPFRE[1]   = (byte) 0xC8;
            freq.mCN = 0x0F;
        }
        return freq;
    }

    private int calculateCRC16(byte[] data, int length) {
        int crc = 0xFFFF;
        for (int i = 0; i < length; i++) {
            crc ^= data[i] & 0xFF;
            for (int j = 0; j < 8; j++) {
                if ((crc & 0x0001) != 0) {
                    crc = (crc >> 1) ^ 0x8408;
                } else {
                    crc >>= 1;
                }
            }
        }
        return crc;
    }

    private byte[] buildStartInventoryRaw() {
        byte[] cmd = new byte[]{ (byte)0xCF, (byte)0xFF, 0x00, 0x01, 0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
        int crc = calculateCRC16(cmd, 10);
        cmd[10] = (byte)((crc >> 8) & 0xFF);
        cmd[11] = (byte)(crc & 0xFF);
        return cmd;
    }

    private void startInventory(MethodChannel.Result result) {
        if (!bleReady || bleCore == null || !bleCore.isConnect()) {
            result.error("BLE_NOT_READY", "Notify/connection hazır deyil", null);
            return;
        }

        new Thread(() -> {
            try {
                if (!ensureReadMode(READ_MODE_RFID)) {
                    new Handler(Looper.getMainLooper()).post(() ->
                            result.error("READ_MODE_FAIL", "Unable to switch to RFID mode", null)
                    );
                    return;
                }

                writeWithRetry(SERVICE_UUID, WRITE_UUID, CmdBuilder.buildStopInventoryCmd());
                try { Thread.sleep(120); } catch (InterruptedException ignored) {}

                byte[] invCmd = CmdBuilder.buildInventoryISOContinueCmd((byte)0x00, 0);
                boolean ok = writeWithRetry(SERVICE_UUID, WRITE_UUID, invCmd);

                if (!ok) {
                    ok = writeWithRetry(SERVICE_UUID, WRITE_UUID, buildStartInventoryRaw());
                }

                if (ok) inventoryRunning = true;

                final boolean okFinal = ok;
                new Handler(Looper.getMainLooper()).post(() -> {
                    if (okFinal) result.success("inventory_started");
                    else         result.error("INVENTORY_FAILED", "start cmd not sent", null);
                });
            } catch (Exception e) {
                inventoryRunning = false;
                new Handler(Looper.getMainLooper()).post(
                        () -> result.error("INVENTORY_EXCEPTION", e.getMessage(), null)
                );
            }
        }).start();
    }

    private void stopInventory(MethodChannel.Result result) {
        try {
            byte[] stopCmd = CmdBuilder.buildStopInventoryCmd();
            boolean sent = writeWithRetry(SERVICE_UUID, WRITE_UUID, stopCmd);
            if (sent) {
                inventoryRunning = false;
                result.success("inventory_stopped");
            } else {
                result.error("INVENTORY_STOP_FAILED", "stop cmd not sent", null);
            }
        } catch (Exception e) {
            result.error("INVENTORY_STOP_EXCEPTION", e.getMessage(), null);
        }
    }

    private void internalStartInventory() {
        try {
            ensureReadMode(READ_MODE_RFID);
            byte[] invCmd = CmdBuilder.buildInventoryISOContinueCmd((byte) 0x00, 0);
            boolean ok = writeWithRetry(SERVICE_UUID, WRITE_UUID, invCmd);
            if (!ok) {
                ok = writeWithRetry(SERVICE_UUID, WRITE_UUID, buildStartInventoryRaw());
            }
            if (ok) inventoryRunning = true;
        } catch (Exception ignore) {}
    }

    private void internalStopInventory() {
        try {
            byte[] stopCmd = CmdBuilder.buildStopInventoryCmd();
            if (writeWithRetry(SERVICE_UUID, WRITE_UUID, stopCmd)) {
                inventoryRunning = false;
            }
        } catch (Exception ignore) {}
    }

    private void readTagByMemoryBank(byte memBank, MethodChannel.Result result) {
        if (!ensureReadMode(READ_MODE_RFID)) {
            result.error("READ_MODE_FAIL", "Unable to switch to RFID mode", null);
            return;
        }

        byte[] accPwd = new byte[]{0x00, 0x00, 0x00, 0x00};
        byte[] wordPtr;

        if (memBank == 0x01) { // EPC
            wordPtr = new byte[]{0x00, 0x02};
        } else {               // TID/USER
            wordPtr = new byte[]{0x00, 0x00};
        }
        byte wordCount = 6;

        byte[] cmd = CmdBuilder.buildReadISOTagCmd(accPwd, memBank, wordPtr, wordCount);
        boolean sent = writeWithRetry(SERVICE_UUID, WRITE_UUID, cmd);

        if (sent) {
            result.success("read_tag_command_sent");
        } else {
            result.error("SEND_FAIL", "Unable to send readTag command", null);
        }
    }

    private String bytesToHex(byte[] bytes) {
        if (bytes == null) return "";
        StringBuilder sb = new StringBuilder();
        for (byte b : bytes) {
            sb.append(String.format("%02X", b));
        }
        return sb.toString();
    }

    public String bytesToHexString(byte[] bytes) {
        if (bytes == null || bytes.length == 0) return "";
        StringBuilder sb = new StringBuilder();
        for (byte b : bytes) {
            sb.append(String.format("%02X", b));
        }
        return sb.toString();
    }

    // ==== Barcode support ====

    private boolean looksLikeSdkFrame(byte[] bytes) {
        return bytes != null
                && bytes.length >= 5
                && (bytes[0] & 0xFF) == 0xCF
                && (bytes[1] & 0xFF) == 0xFF;
    }

    private boolean internalSetReadMode(byte readMode) {
        if (bleCore == null || !bleCore.isConnect() || !waitBleReady(1000)) {
            return false;
        }

        // Mejor esfuerzo: asegurar salida BLE transparente
//        writeWithRetry(SERVICE_UUID, WRITE_UUID, CmdBuilder.buildSetOutputModeCmd((byte) 0x01));
//        try { Thread.sleep(80); } catch (InterruptedException ignored) {}

        boolean ok = writeWithRetry(
                SERVICE_UUID,
                WRITE_UUID,
                CmdBuilder.buildSetReadModeCmd(readMode, new byte[7])
        );

        if (ok) {
            currentReadMode = readMode;

            if (readMode == READ_MODE_RFID) {
                barcodeTriggerActive = false;
                clearBarcodeBuffer();
            } else {
                inventoryRunning = false;
                clearRadarState();
            }
        }

        return ok;
    }

    private boolean ensureReadMode(byte readMode) {
        return currentReadMode == readMode || internalSetReadMode(readMode);
    }

    private void enableBarcodeMode(MethodChannel.Result result) {
        new Thread(() -> {
            try {
                if (!waitBleReady(1000) || bleCore == null || !bleCore.isConnect()) {
                    new Handler(Looper.getMainLooper()).post(() ->
                            result.error("BLE_NOT_READY", "Device not connected or BLE not ready", null)
                    );
                    return;
                }

                if (inventoryRunning) {
                    internalStopInventory();
                    try { Thread.sleep(120); } catch (InterruptedException ignored) {}
                }

                boolean ok = internalSetReadMode(READ_MODE_BARCODE);

                new Handler(Looper.getMainLooper()).post(() -> {
                    if (ok) {
                        result.success("barcode_mode_enabled");
                    } else {
                        result.error("SET_READ_MODE_FAILED", "Unable to switch to barcode mode", null);
                    }
                });
            } catch (Exception e) {
                new Handler(Looper.getMainLooper()).post(() ->
                        result.error("SET_READ_MODE_EXCEPTION", e.getMessage(), null)
                );
            }
        }).start();
    }

    private void enableRfidMode(MethodChannel.Result result) {
        new Thread(() -> {
            try {
                if (!waitBleReady(1000) || bleCore == null || !bleCore.isConnect()) {
                    new Handler(Looper.getMainLooper()).post(() ->
                            result.error("BLE_NOT_READY", "Device not connected or BLE not ready", null)
                    );
                    return;
                }

                boolean ok = internalSetReadMode(READ_MODE_RFID);

                new Handler(Looper.getMainLooper()).post(() -> {
                    if (ok) {
                        result.success("rfid_mode_enabled");
                    } else {
                        result.error("SET_READ_MODE_FAILED", "Unable to switch to RFID mode", null);
                    }
                });
            } catch (Exception e) {
                new Handler(Looper.getMainLooper()).post(() ->
                        result.error("SET_READ_MODE_EXCEPTION", e.getMessage(), null)
                );
            }
        }).start();
    }

    private void startBarcodeScan(MethodChannel.Result result) {
    new Thread(() -> {
        try {
            if (!waitBleReady(1000) || bleCore == null || !bleCore.isConnect()) {
                new Handler(Looper.getMainLooper()).post(() ->
                        result.error("BLE_NOT_READY", "Device not connected or BLE not ready", null)
                );
                return;
            }

            // Si hay un inventario RFID corriendo, lo detenemos antes de escanear
            if (inventoryRunning) {
                internalStopInventory();
                try { Thread.sleep(120); } catch (InterruptedException ignored) {}
            }

            if (!ensureReadMode(READ_MODE_BARCODE)) {
                new Handler(Looper.getMainLooper()).post(() ->
                        result.error("SET_READ_MODE_FAILED", "Unable to switch to barcode mode", null)
                );
                return;
            }

            clearBarcodeBuffer();

            // Comando nativo correcto para disparar la lectura directa de código de barras
            byte[] cmd = CmdBuilder.buildInventoryISOContinueCmd((byte) 0x01, 0x01);
            boolean sent = writeWithRetry(SERVICE_UUID, WRITE_UUID, cmd);

            final boolean okFinal = sent;
            new Handler(Looper.getMainLooper()).post(() -> {
                if (okFinal) {
                    result.success("barcode_scan_triggered");
                } else {
                    result.error("BARCODE_START_FAILED", "Unable to send barcode trigger command", null);
                }
            });
        } catch (Exception e) {
            new Handler(Looper.getMainLooper()).post(() ->
                    result.error("BARCODE_START_EXCEPTION", e.getMessage(), null)
            );
        }
    }).start();
    }

    private void stopBarcodeScan(MethodChannel.Result result) {
        try {
            boolean sent = writeWithRetry(
                    SERVICE_UUID,
                    WRITE_UUID,
                    CmdBuilder.buildReportKeyStateCmd((byte) 0x02)
            );

            barcodeTriggerActive = false;

            if (sent) {
                result.success("barcode_scan_stopped");
            } else {
                result.error("BARCODE_STOP_FAILED", "Unable to send barcode stop command", null);
            }
        } catch (Exception e) {
            result.error("BARCODE_STOP_EXCEPTION", e.getMessage(), null);
        }
    }

    private void handleBarcodeRaw(byte[] bytes) {
        String chunk = new String(bytes, StandardCharsets.UTF_8).replace("\u0000", "");
        if (chunk.isEmpty()) return;

        synchronized (barcodeBufferLock) {
            barcodeBuffer.append(chunk);

            String current = barcodeBuffer.toString().replace('\r', '\n');
            if (current.contains("\n")) {
                String[] parts = current.split("\n", -1);
                barcodeBuffer.setLength(0);

                for (int i = 0; i < parts.length - 1; i++) {
                    emitBarcode(parts[i]);
                }

                String tail = parts[parts.length - 1];
                if (!tail.isEmpty()) {
                    barcodeBuffer.append(tail);
                    scheduleBarcodeFlushLocked();
                } else {
                    clearBarcodeFlushLocked();
                }
                return;
            }

            scheduleBarcodeFlushLocked();
        }
    }

    private void scheduleBarcodeFlushLocked() {
        if (barcodeFlushRunnable != null) {
            barcodeBufferHandler.removeCallbacks(barcodeFlushRunnable);
        }

        barcodeFlushRunnable = () -> {
            String pending;
            synchronized (barcodeBufferLock) {
                pending = barcodeBuffer.toString();
                barcodeBuffer.setLength(0);
                barcodeFlushRunnable = null;
            }
            emitBarcode(pending);
        };

        barcodeBufferHandler.postDelayed(barcodeFlushRunnable, BARCODE_FLUSH_DELAY_MS);
    }

    private void clearBarcodeFlushLocked() {
        if (barcodeFlushRunnable != null) {
            barcodeBufferHandler.removeCallbacks(barcodeFlushRunnable);
            barcodeFlushRunnable = null;
        }
    }

    private void clearBarcodeBuffer() {
        synchronized (barcodeBufferLock) {
            barcodeBuffer.setLength(0);
            clearBarcodeFlushLocked();
        }
    }

    private String sanitizeBarcode(String value) {
        if (value == null) return "";
        return value
                .replace("\u0000", "")
                .replaceAll("[\\p{Cntrl}&&[^\\r\\n\\t]]", "")
                .trim();
    }

    private void emitBarcode(String rawValue) {
        String value = sanitizeBarcode(rawValue);
        if (value.isEmpty()) return;

        Map<String, Object> barcodeMap = new HashMap<>();
        barcodeMap.put("value", value);
        barcodeMap.put("timestamp", System.currentTimeMillis());

        new Handler(Looper.getMainLooper()).post(() -> {
            channel.invokeMethod("onBarcodeRead", barcodeMap);
        });
    }

    // ==== Radar / software mask logic ====

    private void handleInventoryTag(TagInfoBean tag) {
        if (tag == null || tag.mEPCNum == null || tag.mEPCNum.length == 0) return;

        if (!inventoryRunning) inventoryRunning = true;

        String epc = bytesToHexString(tag.mEPCNum);
        int rssi = tag.mRSSI;

        // Radar mode: emit ONLY matching tags, ignore everything else
        if (radarActive) {
            if (matchesRadarFilter(epc)) {
                if (radarUseMask) {
                    Log.d("CHAFON_PLUGIN",
                            "🎯 RADAR MASK MATCH: EPC=" + epc +
                                    ", RSSI=" + rssi +
                                    ", start=" + radarMaskStartAddress +
                                    ", len=" + radarMaskLengthBytes +
                                    ", mask=" + radarMaskHex);
                } else {
                    Log.d("CHAFON_PLUGIN", "🎯 RADAR EPC MATCH: EPC=" + epc + ", RSSI=" + rssi);
                }

                Map<String, Object> radarMap = new HashMap<>();
                radarMap.put("epc", epc);
                radarMap.put("rssi", rssi);
                radarMap.put("timestamp", System.currentTimeMillis());

                if (radarUseMask) {
                    radarMap.put("maskStartAddress", radarMaskStartAddress);
                    radarMap.put("maskLength", radarMaskLengthBytes);
                    radarMap.put("mask", radarMaskHex);
                } else {
                    radarMap.put("targetEpc", radarEpc);
                }

                new Handler(Looper.getMainLooper()).post(() -> {
                    channel.invokeMethod("onRadarSignal", radarMap);
                });
            }
            return;
        }

        Map<String, Object> tagMap = new HashMap<>();
        tagMap.put("epc", epc);
        tagMap.put("rssi", rssi);
        tagMap.put("antenna", tag.mAntenna);
        tagMap.put("timestamp", System.currentTimeMillis());

        new Handler(Looper.getMainLooper()).post(() -> {
            channel.invokeMethod("onTagRead", tagMap);
        });
    }

    @Nullable
    private String normalizeHex(@Nullable String value) {
        if (value == null) return null;

        String normalized = value.trim().replaceAll("\\s+", "");

        if (normalized.startsWith("0x") || normalized.startsWith("0X")) {
            normalized = normalized.substring(2);
        }

        normalized = normalized.toUpperCase();

        if ((normalized.length() % 2) != 0) {
            return null;
        }

        if (!normalized.matches("^[0-9A-F]*$")) {
            return null;
        }

        return normalized;
    }

    private boolean matchesRadarFilter(String epcHex) {
        if (!radarActive || epcHex == null || epcHex.isEmpty()) return false;

        if (radarUseMask) {
            return matchesEpcMask(epcHex, radarMaskStartAddress, radarMaskLengthBytes, radarMaskHex);
        }

        return radarEpc != null && epcHex.equalsIgnoreCase(radarEpc);
    }

    private boolean matchesEpcMask(String epcHex,
                                   int maskStartAddressBytes,
                                   int maskLengthBytes,
                                   String maskHex) {
        String normalizedEpc = normalizeHex(epcHex);
        String normalizedMask = normalizeHex(maskHex);

        if (normalizedEpc == null || normalizedMask == null) return false;
        if (maskStartAddressBytes < 0 || maskLengthBytes < 0) return false;
        if (normalizedMask.length() != maskLengthBytes * 2) return false;

        int startIndex = maskStartAddressBytes * 2;
        int endIndex = startIndex + (maskLengthBytes * 2);

        if (startIndex < 0 || endIndex > normalizedEpc.length()) {
            return false;
        }

        String epcSlice = normalizedEpc.substring(startIndex, endIndex);
        return epcSlice.equalsIgnoreCase(normalizedMask);
    }

    private void clearRadarState() {
        radarEpc = null;
        radarActive = false;
        radarUseMask = false;
        radarMaskStartAddress = 0;
        radarMaskLengthBytes = 0;
        radarMaskHex = null;
    }

    private void startRadarInventory(MethodChannel.Result result) {
        if (!bleReady || bleCore == null || !bleCore.isConnect()) {
            result.error("BLE_NOT_READY", "Notify/connection hazır deyil", null);
            return;
        }

        new Thread(() -> {
            try {
                if (!ensureReadMode(READ_MODE_RFID)) {
                    new Handler(Looper.getMainLooper()).post(() -> {
                        result.error("READ_MODE_FAIL", "Unable to switch to RFID mode", null);
                    });
                    return;
                }

                internalStopInventory();
                try { Thread.sleep(120); } catch (InterruptedException ignored) {}

                byte[] invCmd = CmdBuilder.buildInventoryISOContinueCmd((byte) 0x00, 0);
                boolean ok = writeWithRetry(SERVICE_UUID, WRITE_UUID, invCmd);

                if (!ok) {
                    ok = writeWithRetry(SERVICE_UUID, WRITE_UUID, buildStartInventoryRaw());
                }

                if (ok) inventoryRunning = true;

                final boolean okFinal = ok;
                new Handler(Looper.getMainLooper()).post(() -> {
                    if (okFinal) {
                        result.success("radar_started");
                    } else {
                        result.error("RADAR_START_FAIL", "Radar izləməsi başladılmadı", null);
                    }
                });
            } catch (Exception e) {
                inventoryRunning = false;
                new Handler(Looper.getMainLooper()).post(() -> {
                    result.error("RADAR_START_EXCEPTION", e.getMessage(), null);
                });
            }
        }).start();
    }

    private void startRadarTracking(String epc, MethodChannel.Result result) {
        String normalizedEpc = normalizeHex(epc);

        if (normalizedEpc == null || normalizedEpc.isEmpty()) {
            result.error("INVALID_ARGUMENT", "EPC must be valid HEX", null);
            return;
        }

        radarEpc = normalizedEpc;
        radarUseMask = false;
        radarMaskStartAddress = 0;
        radarMaskLengthBytes = 0;
        radarMaskHex = null;
        radarActive = true;

        startRadarInventory(result);
    }

    private void startRadarMasked(int maskStartAddress, int maskLength, String mask, MethodChannel.Result result) {
        if (maskStartAddress < 0 || maskStartAddress > 31) {
            result.error("INVALID_ARGUMENT", "maskStartAddress must be in range 0..31", null);
            return;
        }

        if (maskLength < 0 || maskLength > 31) {
            result.error("INVALID_ARGUMENT", "maskLength must be in range 0..31", null);
            return;
        }

        String normalizedMask = normalizeHex(mask);
        if (normalizedMask == null) {
            result.error("INVALID_ARGUMENT", "mask must be valid HEX with even length", null);
            return;
        }

        if (normalizedMask.length() != maskLength * 2) {
            result.error(
                    "INVALID_ARGUMENT",
                    "maskLength is in BYTES, so mask HEX length must equal maskLength * 2",
                    null
            );
            return;
        }

        radarEpc = null;
        radarUseMask = true;
        radarMaskStartAddress = maskStartAddress;
        radarMaskLengthBytes = maskLength;
        radarMaskHex = normalizedMask;
        radarActive = true;

        startRadarInventory(result);
    }

    private void stopRadarTracking(MethodChannel.Result result) {
        clearRadarState();

        byte[] stopCmd = CmdBuilder.buildStopInventoryCmd();
        writeWithRetry(SERVICE_UUID, WRITE_UUID, stopCmd);

        inventoryRunning = false;
        result.success("radar_stopped");
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (bleCore != null) {
            bleCore.disconnectedDevice();
            bleCore.setOnNotifyCallback(null);
            bleCore.setIConnectDoneCallback(null);
            bleCore.setIBleDisConnectCallback(null);
        }
        discoveredDevices.clear();
        channel.setMethodCallHandler(null);

        bleReady = false;
        latestAllParam = null;
        inventoryRunning = false;
        clearRadarState();

        currentReadMode = READ_MODE_RFID;
        barcodeTriggerActive = false;
        clearBarcodeBuffer();
    }
}