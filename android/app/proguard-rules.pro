# App-specific reflection rules; no image recognition dependencies in V1.0.0.

# Preserve the journal verification seam across R8 class merging. Names may still shrink.
-keep,allowobfuscation class com.qinghe.qinghe_timetable.AlarmStore {
    public <init>(android.content.Context);
    public java.util.Map schedule(boolean);
}
