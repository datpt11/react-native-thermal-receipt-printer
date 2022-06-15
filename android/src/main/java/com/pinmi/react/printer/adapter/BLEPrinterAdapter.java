package com.pinmi.react.printer.adapter;

import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothSocket;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.ColorFilter;
import android.graphics.ColorMatrix;
import android.graphics.ColorMatrixColorFilter;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.util.Base64;
import android.util.Log;
import android.widget.Toast;

//import com.dantsu.escposprinter.EscPosPrinterCommands;
import com.facebook.react.bridge.ActivityEventListener;
import com.facebook.react.bridge.Callback;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReadableMap;

import java.io.IOException;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import static android.app.Activity.RESULT_OK;
/**
 * Created by xiesubin on 2017/9/21.
 */

public class BLEPrinterAdapter implements PrinterAdapter{


    private static BLEPrinterAdapter mInstance;


    private String LOG_TAG = "RNBLEPrinter";

    private BluetoothDevice mBluetoothDevice;
    private BluetoothSocket mBluetoothSocket;


    private ReactApplicationContext mContext;



    private BLEPrinterAdapter(){}

    public static BLEPrinterAdapter getInstance() {
        if(mInstance == null) {
            mInstance = new BLEPrinterAdapter();
        }
        return mInstance;
    }

    @Override
    public void init(ReactApplicationContext reactContext, Callback successCallback, Callback errorCallback) {
        this.mContext = reactContext;
        BluetoothAdapter bluetoothAdapter = getBTAdapter();
        if(bluetoothAdapter == null) {
            errorCallback.invoke("No bluetooth adapter available");
            return;
        }
        if(!bluetoothAdapter.isEnabled()) {
            errorCallback.invoke("bluetooth adapter is not enabled");
            return;
        }else{
            successCallback.invoke();
        }

    }

    private static BluetoothAdapter getBTAdapter() {
        return BluetoothAdapter.getDefaultAdapter();
    }

    @Override
    public List<PrinterDevice> getDeviceList(Callback errorCallback) {
        BluetoothAdapter bluetoothAdapter = getBTAdapter();
        List<PrinterDevice> printerDevices = new ArrayList<>();
        if(bluetoothAdapter == null) {
            errorCallback.invoke("No bluetooth adapter available");
            return printerDevices;
        }
        if (!bluetoothAdapter.isEnabled()) {
            errorCallback.invoke("bluetooth is not enabled");
            return printerDevices;
        }
        Set<BluetoothDevice> pairedDevices = getBTAdapter().getBondedDevices();
        for (BluetoothDevice device : pairedDevices) {
            printerDevices.add(new BLEPrinterDevice(device));
        }
        return printerDevices;
    }

    @Override
    public void selectDevice(PrinterDeviceId printerDeviceId, Callback successCallback, Callback errorCallback) {
        BluetoothAdapter bluetoothAdapter = getBTAdapter();
        if(bluetoothAdapter == null) {
            errorCallback.invoke("No bluetooth adapter available");
            return;
        }
        if (!bluetoothAdapter.isEnabled()) {
            errorCallback.invoke("bluetooth is not enabled");
            return;
        }
        BLEPrinterDeviceId blePrinterDeviceId = (BLEPrinterDeviceId)printerDeviceId;
        if(this.mBluetoothDevice != null){
            if(this.mBluetoothDevice.getAddress().equals(blePrinterDeviceId.getInnerMacAddress()) && this.mBluetoothSocket != null){
                Log.v(LOG_TAG, "do not need to reconnect");
                successCallback.invoke(new BLEPrinterDevice(this.mBluetoothDevice).toRNWritableMap());
                return;
            }else{
                closeConnectionIfExists();
            }
        }
        Set<BluetoothDevice> pairedDevices = getBTAdapter().getBondedDevices();

        for (BluetoothDevice device : pairedDevices) {
            if(device.getAddress().equals(blePrinterDeviceId.getInnerMacAddress())){

                try{
                    connectBluetoothDevice(device);
                    successCallback.invoke(new BLEPrinterDevice(this.mBluetoothDevice).toRNWritableMap());
                    return;
                }catch (IOException e){
                    e.printStackTrace();
                    errorCallback.invoke(e.getMessage());
                    return;
                }
            }
        }
        String errorText = "Can not find the specified printing device, please perform Bluetooth pairing in the system settings first.";
        Toast.makeText(this.mContext, errorText, Toast.LENGTH_LONG).show();
        errorCallback.invoke(errorText);
        return;
    }

    private void connectBluetoothDevice(BluetoothDevice device) throws IOException{
        UUID uuid = UUID.fromString("00001101-0000-1000-8000-00805f9b34fb");
        this.mBluetoothSocket = device.createRfcommSocketToServiceRecord(uuid);
        this.mBluetoothSocket.connect();
        this.mBluetoothDevice = device;//最后一步执行

    }

    @Override
    public void closeConnectionIfExists() {
        try{
            if(this.mBluetoothSocket != null){
                this.mBluetoothSocket.close();
                this.mBluetoothSocket = null;
            }
        }catch(IOException e){
            e.printStackTrace();
        }

        if(this.mBluetoothDevice != null) {
            this.mBluetoothDevice = null;
        }
    }

    @Override
    public void printRawData(String rawBase64Data, Callback errorCallback) {
        if(this.mBluetoothSocket == null){
            errorCallback.invoke("bluetooth connection is not built, may be you forgot to connectPrinter");
            return;
        }
        final String rawData = rawBase64Data;
        final BluetoothSocket socket = this.mBluetoothSocket;
        Log.v(LOG_TAG, "start to print raw data " + rawBase64Data);
        new Thread(new Runnable() {
            @Override
            public void run() {
                byte [] bytes = Base64.decode(rawData, Base64.DEFAULT);
                try{
                    OutputStream printerOutputStream = socket.getOutputStream();
                    printerOutputStream.write(bytes, 0, bytes.length);
                    printerOutputStream.flush();
                }catch (IOException e){
                    Log.e(LOG_TAG, "failed to print data" + rawData);
                    e.printStackTrace();
                }

            }
        }).start();
    }

//    @Override
//    public void printRawImage(String rawBase64Data, Callback errorCallback) {
//        if(this.mBluetoothSocket == null){
//            errorCallback.invoke("bluetooth connection is not built, may be you forgot to connectPrinter");
//            return;
//        }
//        final String rawData = rawBase64Data;
//        final BluetoothSocket socket = this.mBluetoothSocket;
//        Log.v(LOG_TAG, "start to print raw data " + rawBase64Data);
//        new Thread(new Runnable() {
//            @Override
//            public void run() {
//                byte[] decodeBase64ImageString = Base64.decode(rawData, Base64.DEFAULT);
//                Bitmap bitmapImage = BitmapFactory.decodeByteArray(decodeBase64ImageString, 0, decodeBase64ImageString.length);
//                final Bitmap resizeBitmapImage = resizeImage(bitmapImage,408,false);
//                final byte[] initPrinter = initializePrinter();
//                byte[] bytes = EscPosPrinterCommands.bitmapToBytes(resizeBitmapImage);
//
//                try{
//                    OutputStream printerOutputStream = socket.getOutputStream();
//                    printerOutputStream.write(initPrinter,0,initPrinter.length);
//                    printerOutputStream.write(bytes, 0, bytes.length);
//                    printerOutputStream.flush();
//                }catch (IOException e){
//                    Log.e(LOG_TAG, "failed to print data" + rawData);
//                    e.printStackTrace();
//                }
//
//            }
//        }).start();
//    }

    @Override
    public void printRawImage(String image, ReadableMap options, Callback errorCallback) {
        if (this.mBluetoothSocket == null) {
            errorCallback.invoke("bluetooth connection is not built, may be you forgot to connectPrinter");
            return;
        }
        Log.v(LOG_TAG, "image is:  " + image);
        final int width = options.getInt("width");
//        Log.d("width", "width" + width);
        byte[] decodeBase64ImageString = Base64.decode(image, Base64.DEFAULT);
        Bitmap bitmapImage = BitmapFactory.decodeByteArray(decodeBase64ImageString, 0, decodeBase64ImageString.length);
        Log.d("BLEPrinterModule", "decodeBase64ImageString is:  " + decodeBase64ImageString
                + " and bitmapImage: " + bitmapImage);

        if(bitmapImage !=null){
            bitmapImage = resizeImage(bitmapImage,width,false);
            final byte[] initPrinter = initializePrinter();
            final byte[] cutPrinter = selectCutPagerModerAndCutPager(66,1);
            final byte[] data = rasterBmpToSendData(0,bitmapImage, width);
//            final byte[] data = EscPosPrinterCommands.bitmapToBytes(bitmapImage);
            final BluetoothSocket socket = this.mBluetoothSocket;
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

