package com.pinmi.react.printer.adapter;

import android.bluetooth.BluetoothSocket;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.ColorFilter;
import android.graphics.ColorMatrix;
import android.graphics.ColorMatrixColorFilter;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.net.wifi.WifiManager;
import android.util.Base64;
import android.util.Log;

//import com.dantsu.escposprinter.EscPosPrinterCommands;
import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.Callback;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.WritableArray;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.modules.core.DeviceEventManagerModule;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.util.ArrayList;
import java.util.List;

/**
 * Created by xiesubin on 2017/9/22.
 */

public class NetPrinterAdapter implements PrinterAdapter {
    private static NetPrinterAdapter mInstance;
    private ReactApplicationContext mContext;
    private String LOG_TAG = "RNNetPrinter";
    private NetPrinterDevice mNetDevice;

    //    {TODO- support other ports later}
//    private int[] PRINTER_ON_PORTS = {515, 3396, 9100, 9303};

    private int[] PRINTER_ON_PORTS = {9100};
    private static final String EVENT_SCANNER_RESOLVED = "scannerResolved";
    private static final String EVENT_SCANNER_RUNNING = "scannerRunning";

    private Socket mSocket;

    private boolean isRunning = false;

    private NetPrinterAdapter() {

    }

    public static NetPrinterAdapter getInstance() {
        if (mInstance == null) {
            mInstance = new NetPrinterAdapter();

        }
        return mInstance;
    }

    @Override
    public void init(ReactApplicationContext reactContext, Callback successCallback, Callback errorCallback) {
        this.mContext = reactContext;
        successCallback.invoke();
    }

    @Override
    public List<PrinterDevice> getDeviceList(Callback errorCallback) {
        // errorCallback.invoke("do not need to invoke get device list for net printer");
        // Use emitter instancee get devicelist to non block main thread
        this.scan();
        List<PrinterDevice> printerDevices = new ArrayList<>();
        return printerDevices;
    }

    private void scan() {
        if (isRunning) return;
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    isRunning = true;
                    emitEvent(EVENT_SCANNER_RUNNING, isRunning);

                    WifiManager wifiManager = (WifiManager) mContext.getApplicationContext().getSystemService(Context.WIFI_SERVICE);
                    String ipAddress = ipToString(wifiManager.getConnectionInfo().getIpAddress());
                    WritableArray array = Arguments.createArray();


                    String prefix = ipAddress.substring(0, ipAddress.lastIndexOf('.') + 1);
                    int suffix = Integer.parseInt(ipAddress.substring(ipAddress.lastIndexOf('.') + 1, ipAddress.length()));

                    for (int i = 0; i <= 255; i++) {
                        if (i == suffix) continue;
                        ArrayList<Integer> ports = getAvailablePorts(prefix + i);
                        if (!ports.isEmpty()) {
                            WritableMap payload = Arguments.createMap();

                            payload.putString("host", prefix + i);
                            payload.putInt("port", 9100);

                            array.pushMap(payload);
                        }
                    }

                    emitEvent(EVENT_SCANNER_RESOLVED, array);

                } catch (NullPointerException ex) {
                    Log.i(LOG_TAG, "No connection");
                } finally {
                    isRunning = false;
                    emitEvent(EVENT_SCANNER_RUNNING, isRunning);
                }
            }
        }).start();
    }

    private void emitEvent(String eventName, Object data) {
        if (mContext != null) {
            mContext.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class)
                    .emit(eventName, data);
        }
    }

    private ArrayList<Integer> getAvailablePorts(String address) {
        ArrayList<Integer> ports = new ArrayList<>();
        for (int port : PRINTER_ON_PORTS) {
            if (crunchifyAddressReachable(address, port)) ports.add(port);
        }
        return ports;
    }


    private static boolean crunchifyAddressReachable(String address, int port) {
        try {

            try (Socket crunchifySocket = new Socket()) {
                // Connects this socket to the server with a specified timeout value.
                crunchifySocket.connect(new InetSocketAddress(address, port), 100);
            }
            // Return true if connection successful
            return true;
        } catch (IOException exception) {
            exception.printStackTrace();
            return false;
        }
    }

    private String ipToString(int ip) {
        return (ip & 0xFF) + "." +
                ((ip >> 8) & 0xFF) + "." +
                ((ip >> 16) & 0xFF) + "." +
                ((ip >> 24) & 0xFF);
    }

    @Override
    public void selectDevice(PrinterDeviceId printerDeviceId, Callback sucessCallback, Callback errorCallback) {
        NetPrinterDeviceId netPrinterDeviceId = (NetPrinterDeviceId) printerDeviceId;

        if (this.mSocket != null && !this.mSocket.isClosed() && mNetDevice.getPrinterDeviceId().equals(netPrinterDeviceId)) {
            Log.i(LOG_TAG, "already selected device, do not need repeat to connect");
            sucessCallback.invoke(this.mNetDevice.toRNWritableMap());
            return;
        }

        try {
            Socket socket = new Socket(netPrinterDeviceId.getHost(), netPrinterDeviceId.getPort());
            if (socket.isConnected()) {
                closeConnectionIfExists();
                this.mSocket = socket;
                this.mNetDevice = new NetPrinterDevice(netPrinterDeviceId.getHost(), netPrinterDeviceId.getPort());
                sucessCallback.invoke(this.mNetDevice.toRNWritableMap());
            } else {
                errorCallback.invoke("unable to build connection with host: " + netPrinterDeviceId.getHost() + ", port: " + netPrinterDeviceId.getPort());
                return;
            }
        } catch (IOException e) {
            e.printStackTrace();
            errorCallback.invoke("failed to connect printer: " + e.getMessage());
        }
    }

    @Override
    public void closeConnectionIfExists() {
        if (this.mSocket != null) {
            if (!this.mSocket.isClosed()) {
                try {
                    this.mSocket.close();
                } catch (IOException e) {
                    e.printStackTrace();
                }
            }

            this.mSocket = null;

        }
    }

    @Override
    public void printRawData(String rawBase64Data, Callback errorCallback) {
        if (this.mSocket == null) {
            errorCallback.invoke("bluetooth connection is not built, may be you forgot to connectPrinter");
            return;
        }
        final String rawData = rawBase64Data;
        final Socket socket = this.mSocket;
        Log.v(LOG_TAG, "start to print raw data " + rawBase64Data);
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    byte[] bytes = Base64.decode(rawData, Base64.DEFAULT);
                    OutputStream printerOutputStream = socket.getOutputStream();
                    printerOutputStream.write(bytes, 0, bytes.length);
                    printerOutputStream.flush();
                } catch (IOException e) {
                    Log.e(LOG_TAG, "failed to print data" + rawData);
                    e.printStackTrace();
                }
            }
        }).start();

    }

    @Override
    public void printRawImage(String image, ReadableMap options, Callback errorCallback) {
        if (this.mSocket == null) {
            errorCallback.invoke("bluetooth connection is not built, may be you forgot to connectPrinter");
            return;
        }
        Log.v(LOG_TAG, "image is:  " + image);
        final int width = options.getInt("width");
        byte[] decodeBase64ImageString = Base64.decode(image, Base64.DEFAULT);
        Bitmap bitmapImage = BitmapFactory.decodeByteArray(decodeBase64ImageString, 0, decodeBase64ImageString.length);
        Log.d("NetPrinterModule", "decodeBase64ImageString is:  " + decodeBase64ImageString
                + " and bitmapImage: " + bitmapImage);

        if(bitmapImage !=null){
            bitmapImage = resizeImage(bitmapImage,width,false);
            final byte[] initPrinter = initializePrinter();
            final byte[] cutPrinter = selectCutPagerModerAndCutPager(66,1);
            final byte[] data = rasterBmpToSendData(0,bitmapImage, width);
//            final byte[] data = EscPosPrinterCommands.bitmapToBytes(bitmapImage);
            final Socket socket = this.mSocket;
            new Thread(new Runnable() {
                @Override
                public void run() {
                    try {
                        OutputStream printerOutputStream = socket.getOutputStream();
                        printerOutputStream.write(initPrinter,0,initPrinter.length);
                        printerOutputStream.write(data,0,data.length);
                        printerOutputStream.write(cutPrinter,0,cutPrinter.length);
                        printerOutputStream.flush();
                    } catch (IOException e) {
                        Log.e(LOG_TAG, "failed to print image" );
                        e.printStackTrace();
                    }
                }
            }).start();
        } else{
            Log.d("NetPrinterModule", "bitmapImage is null");
            return;
        }

    }


    public static byte[] rasterBmpToSendData(final int m, final Bitmap mBitmap, final int pagewidth) {
        Bitmap bitmap = toGrayscale(mBitmap);

        bitmap = convertGreyImgByFloyd(bitmap);

        final int width = bitmap.getWidth();
        final int height = bitmap.getHeight();
        final int[] pixels = new int[width * height];
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height);
        final byte[] data = getbmpdata(pixels, width, height);
        final int n = (width + 7) / 8;
        final byte xL = (byte)(n % 256);
        final byte xH = (byte)(n / 256);
        final int x = (height + 23) / 24;
        final List<Byte> list = new ArrayList<Byte>();
        final byte[] head = { 29, 118, 48, (byte)m, xL, xH, 24, 0 };
        int mL = 0;
        int mH = 0;
        if (width >= pagewidth) {
            mL = 0;
            mH = 0;
        } else {
            mL = (pagewidth - width) / 2 % 256;
            mH = (pagewidth - width) / 2 / 256;
        }

        final byte[] aligndata = setAbsolutePrintPosition(mL, mH);
        for (int i = 0; i < x; ++i) {
            byte[] newdata;
            if (i == x - 1) {
                if (height % 24 == 0) {
                    head[6] = 24;
                    newdata = new byte[n * 24];
                    System.arraycopy(data, 24 * i * n, newdata, 0, 24 * n);
                }
                else {
                    head[6] = (byte)(height % 24);
                    newdata = new byte[height % 24 * n];
                    System.arraycopy(data, 24 * i * n, newdata, 0, height % 24 * n);
                }
            }
            else {
                newdata = new byte[n * 24];
                System.arraycopy(data, 24 * i * n, newdata, 0, 24 * n);
            }
            if (width < pagewidth) {
                byte[] array;
                for (int length = (array = aligndata).length, k = 0; k < length; ++k) {
                    final byte b = array[k];
                    list.add(b);
                }
            }
            byte[] array2;
            for (int length2 = (array2 = head).length, l = 0; l < length2; ++l) {
                final byte b = array2[l];
                list.add(b);
            }
            byte[] array3;
            for (int length3 = (array3 = newdata).length, n2 = 0; n2 < length3; ++n2) {
                final byte b = array3[n2];
                list.add(b);
            }
        }
        final byte[] byteData = new byte[list.size()];
        for (int j = 0; j < byteData.length; ++j) {
            byteData[j] = list.get(j);
        }
        return byteData;
    }

    private static Bitmap toGrayscale(final Bitmap bmpOriginal) {
        final int height = bmpOriginal.getHeight();
        final int width = bmpOriginal.getWidth();
        final Bitmap bmpGrayscale = Bitmap.createBitmap(width, height, Bitmap.Config.RGB_565);
        final Canvas c = new Canvas(bmpGrayscale);
        final Paint paint = new Paint();
        final ColorMatrix cm = new ColorMatrix();
        cm.setSaturation(0.0f);
        final ColorMatrixColorFilter f = new ColorMatrixColorFilter(cm);
        paint.setColorFilter((ColorFilter)f);
        c.drawBitmap(bmpOriginal, 0.0f, 0.0f, paint);
        return bmpGrayscale;
    }

    private static Bitmap convertGreyImgByFloyd(final Bitmap img) {
        final int width = img.getWidth();
        final int height = img.getHeight();
        final int[] pixels = new int[width * height];
        img.getPixels(pixels, 0, width, 0, 0, width, height);
        final int[] gray = new int[height * width];
        for (int i = 0; i < height; ++i) {
            for (int j = 0; j < width; ++j) {
                final int grey = pixels[width * i + j];
                final int red = (grey & 0xFF0000) >> 16;
                gray[width * i + j] = red;
            }
        }
        int e = 0;
        for (int k = 0; k < height; ++k) {
            for (int l = 0; l < width; ++l) {
                final int g = gray[width * k + l];
                if (g >= 128) {
                    pixels[width * k + l] = -1;
                    e = g - 255;
                }
                else {
                    pixels[width * k + l] = -16777216;
                    e = g - 0;
                }
                if (l < width - 1 && k < height - 1) {
                    final int[] array = gray;
                    final int n = width * k + l + 1;
                    array[n] += 3 * e / 8;
                    final int[] array2 = gray;
                    final int n2 = width * (k + 1) + l;
                    array2[n2] += 3 * e / 8;
                    final int[] array3 = gray;
                    final int n3 = width * (k + 1) + l + 1;
                    array3[n3] += e / 4;
                }
                else if (l == width - 1 && k < height - 1) {
                    final int[] array4 = gray;
                    final int n4 = width * (k + 1) + l;
                    array4[n4] += 3 * e / 8;
                }
                else if (l < width - 1 && k == height - 1) {
                    final int[] array5 = gray;
                    final int n5 = width * k + l + 1;
                    array5[n5] += e / 4;
                }
            }
        }
        final Bitmap mBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.RGB_565);
        mBitmap.setPixels(pixels, 0, width, 0, 0, width, height);
        return mBitmap;
    }

    private static byte[] getbmpdata(final int[] b, final int w, final int h) {
        final int n = (w + 7) / 8;
        final byte[] data = new byte[n * h];
        final byte mask = 1;
        for (int y = 0; y < h; ++y) {
            for (int x = 0; x < n * 8; ++x) {
                if (x < w) {
                    if ((b[y * w + x] & 0xFF0000) >> 16 != 0) {
                        final byte[] array = data;
                        final int n2 = y * n + x / 8;
                        array[n2] |= (byte)(mask << 7 - x % 8);
                    }
                }
                else if (x >= w) {
                    final byte[] array2 = data;
                    final int n3 = y * n + x / 8;
                    array2[n3] |= (byte)(mask << 7 - x % 8);
                }
            }
        }
        for (int i = 0; i < data.length; ++i) {
            data[i] ^= -1;
        }
        return data;
    }

    public static byte[] setAbsolutePrintPosition(final int m, final int n) {
        final byte[] data = { 27, 36, (byte)m, (byte)n };
        return data;
    }


    public static byte[] initializePrinter() {
        final byte[] data = { 27, 64 };
        return data;
    }

    public static byte[] selectCutPagerModerAndCutPager(final int m, final int n) {
        if (m != 66) {
            return new byte[0];
        }
        final byte[] data = { 29, 86, (byte)m, (byte)n };
        return data;
    }

    public static Bitmap resizeImage(Bitmap bitmap, int w,boolean ischecked)
    {

        Bitmap BitmapOrg = bitmap;
        Bitmap resizedBitmap = null;
        int width = BitmapOrg.getWidth();
        int height = BitmapOrg.getHeight();
        if (width<=w) {
            return bitmap;
        }
        if (!ischecked) {
            int newWidth = w;
            int newHeight = height*w/width;

            float scaleWidth = ((float) newWidth) / width;
            float scaleHeight = ((float) newHeight) / height;

            Matrix matrix = new Matrix();
            matrix.postScale(scaleWidth, scaleHeight);
            // if you want to rotate the Bitmap
            // matrix.postRotate(45);
            resizedBitmap = Bitmap.createBitmap(BitmapOrg, 0, 0, width,
                    height, matrix, true);
        }else {
            resizedBitmap=Bitmap.createBitmap(BitmapOrg, 0, 0, w, height);
        }

        return resizedBitmap;
    }
}
