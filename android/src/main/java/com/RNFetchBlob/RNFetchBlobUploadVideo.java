package com.RNFetchBlob;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

import com.RNFetchBlob.videoupload.TXUGCPublish;
import com.RNFetchBlob.videoupload.TXUGCPublishTypeDef;
import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.Callback;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.modules.core.DeviceEventManagerModule;

import java.lang.ref.WeakReference;
import java.util.HashMap;

public class RNFetchBlobUploadVideo extends BroadcastReceiver implements Runnable {

    public static HashMap<String, TXUGCPublish> taskTable = new HashMap<>();
    ReadableMap options;
    String taskId;
    Callback callback;
    ReactApplicationContext context;

    public RNFetchBlobUploadVideo(ReadableMap options, String taskId, ReactApplicationContext context, final Callback callback) {
        this.options = options;
        this.taskId = taskId;
        this.callback = callback;
        this.context = context;
    }


    @Override
    public void run() {
        uploadFile(this.options);
    }

    private void releaseTaskResource() {
        if(RNFetchBlobUploadVideo.taskTable.containsKey(taskId))
            RNFetchBlobUploadVideo.taskTable.remove(taskId);
        if(RNFetchBlobReq.uploadProgressReport.containsKey(taskId))
            RNFetchBlobReq.uploadProgressReport.remove(taskId);
    }

    public void uploadFile(ReadableMap map) {
        TXUGCPublishTypeDef.TXPublishParam param = new TXUGCPublishTypeDef.TXPublishParam();
        param.signature = map.getString("sign");
        param.videoPath = map.getString("fileURL");

        WeakReference<RNFetchBlobUploadVideo> thisRef = new WeakReference<RNFetchBlobUploadVideo>(this);
        TXUGCPublish mVideoPublish = new TXUGCPublish(this.context, "1304755944");
        RNFetchBlobUploadVideo.taskTable.put(taskId, mVideoPublish);
        mVideoPublish.setListener(new TXUGCPublishTypeDef.ITXVideoPublishListener() {
            @Override
            public void onPublishProgress(long uploadBytes, long totalBytes) {
                Log.d("upload video", "onPublishProgress: " + uploadBytes + "--" + totalBytes);
                RNFetchBlobProgressConfig reportConfig = RNFetchBlobReq.getReportUploadProgress(thisRef.get().taskId);

                double progress = uploadBytes * 1.0 / totalBytes;

                if (reportConfig != null && reportConfig.shouldReport((float) progress)) {
                    WritableMap args = Arguments.createMap();
                    args.putString("taskId", taskId);
                    args.putString("written", String.valueOf(uploadBytes));
                    args.putString("total", String.valueOf(totalBytes));
                    args.putDouble("percent", progress);
                    thisRef.get().context.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class)
                            .emit(RNFetchBlobConst.EVENT_PROGRESS, args);
                }
            }
            @Override
            public void onPublishComplete(TXUGCPublishTypeDef.TXPublishResult result) {
                Log.d("upload video", "onPublishComplete: " + result.retCode + " Msg:" + (result.retCode == 0 ? result.videoURL : result.descMsg));
                if (result.retCode == 0) {
                    WritableMap map = Arguments.createMap();
                    map.putString("videoURL", result.videoURL);
                    map.putString("videoId", result.videoId);
                    thisRef.get().callback.invoke(map, null);
                } else {
                    thisRef.get().callback.invoke(null, result.descMsg);
                }
                thisRef.get().releaseTaskResource();
            }
        });

        mVideoPublish.publishVideo(param);
    }

    @Override
    public void onReceive(Context context, Intent intent) {

    }
}
