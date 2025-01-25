data:extend({
    {
        type = "string-setting",
        name = "mtn-file-log-level",
        setting_type = "runtime-global",
        default_value = "INFO",
        allowed_values = {
            "TRACE",
            "DEBUG",
            "INFO",
            "ERROR",
            "SILENT",
        }
    },
    {
        type = "string-setting",
        name = "mtn-user-log-level",
        setting_type = "runtime-global",
        default_value = "ERROR",
        allowed_values = {
            "TRACE",
            "DEBUG",
            "INFO",
            "ERROR",
            "SILENT",
        }
    },
})
