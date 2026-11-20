# The WorkManager version pulled in by Google Mobile Ads uses Room reflection.
-keep class androidx.work.impl.WorkDatabase_Impl {
    public <init>();
}
