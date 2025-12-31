local LrLogger = import "LrLogger"
local logger = LrLogger("MirrorPublish")
logger:enable("logfile")

logger:trace("RunPublish.lua loaded")

local LrApplication = import "LrApplication"
local LrDialogs = import "LrDialogs"
local LrView = import "LrView"
local LrBinding = import "LrBinding"
local LrPrefs = import "LrPrefs"
local LrExportSession = import "LrExportSession"
local LrFileUtils = import "LrFileUtils"
local LrFunctionContext = import "LrFunctionContext"
local LrTasks = import "LrTasks"

local SOURCE_ROOT = "/Volumes/T9/Bilder/Original"
local DEST_ROOT = "/Volumes/T9/Bilder/Published"

local prefs = LrPrefs.prefsForPlugin()

----------------------------------------------------------------------
-- Dialog: ask for rating + quality
----------------------------------------------------------------------

local function log(message)
    logger:trace(message)
end

local function promptForSettings()
    return LrFunctionContext.callWithContext("promptForSettings", function(context)

        local f = LrView.osFactory()
        local props = LrBinding.makePropertyTable(context)

        props.minRating = prefs.minRating or 2
        props.jpgQuality = prefs.jpgQuality or 80

        local result = LrDialogs.presentModalDialog {
            title = "Publish JPG Settings",
            contents = f:column{
                spacing = f:control_spacing(),

                f:row{f:static_text{
                    title = "Minimum rating (0–5):"
                }, f:edit_field{
                    value = LrView.bind("minRating"),
                    width_in_digits = 2
                }},

                f:row{f:static_text{
                    title = "JPEG quality (1–100):"
                }, f:edit_field{
                    value = LrView.bind("jpgQuality"),
                    width_in_digits = 3
                }}
            },
            propertyTable = props
        }

        if result ~= "ok" then
            return nil
        end

        local rating = tonumber(props.minRating)
        local quality = tonumber(props.jpgQuality)

        if not rating or rating < 0 or rating > 5 then
            LrDialogs.message("Invalid rating", "Rating must be between 0 and 5.")
            return nil
        end

        if not quality or quality < 1 or quality > 100 then
            LrDialogs.message("Invalid quality", "JPEG quality must be between 1 and 100.")
            return nil
        end

        prefs.minRating = rating
        prefs.jpgQuality = quality

        return rating, quality
    end)
end

----------------------------------------------------------------------
-- Main task
----------------------------------------------------------------------

LrTasks.startAsyncTask(function()

    local catalog = LrApplication.activeCatalog()
    local photos = catalog:getTargetPhotos()

    -- local minRating, jpgQuality = promptForSettings()
    -- log("Returned from promptForSettings")
    local minRating = 4
    local jpgQuality = 80

    log("Using fixed props:")
    log(minRating)
    log(jpgQuality)

    if not minRating then
        log("No minRating")
        return
    end

    -- Find the selected folders
    local sources = catalog:getActiveSources()
    local selectedFolders = {}

    for _, source in ipairs(sources) do
        if source:type() == "LrFolder" then
            table.insert(selectedFolders, source)
        end
    end

    if #selectedFolders < 1 then
        log("No folders selected")
        LrDialogs.message("No folders selected", "Please select one or more folders.")
        return
    end

    -- Find photos in the selected folders and subfolders
    local photosToExport = {}
    for _, folder in ipairs(selectedFolders) do
        local path = folder:getPath()
        log("Selected folder: " .. path)
        local photos = folder:getPhotos(true)
        for _, photo in ipairs(photos) do
            local rating = photo:getRawMetadata("rating") or 0
            if rating >= minRating then
                table.insert(photosToExport, photo)
            end
        end
    end

    if #photosToExport < 1 then
        log("No photos to export")
        LrDialogs.message("No photos to export", "Found no photos with rating " .. minRating .. " or more")
        return
    end

    -- Find all source folders sort photos by source folder
    local sourceFolders = {}
    for _, photo in ipairs(photosToExport) do
        local path = photo:getRawMetadata("path")
        local folderPath = path:match("(.+)/[^/]+$")
        if sourceFolders[folderPath] == nil then
            sourceFolders[folderPath] = {}
        end
        table.insert(sourceFolders[folderPath], photo)
    end



    -- Export photos, one session per source folder
    for folder, photos in pairs(sourceFolders) do
        local relative = folder:sub(#SOURCE_ROOT + 1)
        local destFolder = DEST_ROOT .. relative

        if not LrFileUtils.exists(destFolder) then
            log("Creating folder: " .. destFolder)
            LrFileUtils.createAllDirectories(destFolder)
        end

        log("Exporting " .. #photos .. " photos from " .. folder .. " to " .. destFolder)

        local exportSettings = {
            LR_export_destinationType = "specificFolder",
            LR_export_destinationPathPrefix = destFolder,
            LR_format = "JPEG",
            LR_jpeg_quality = jpgQuality / 100,
            LR_size_doConstrain = false,
            LR_collisionHandling = "overwrite",
            LR_metadata_includeAll = true
        }

        local session = LrExportSession {
            photosToExport = photos,
            exportSettings = exportSettings
        }

        session:doExportOnCurrentTask()



    end



    -- if #skipped > 0 then
    --     LrDialogs.message("Publish complete",
    --         "Exported photos, but skipped " .. #skipped .. " photo(s) not under:\n" .. SOURCE_ROOT)
    -- else
    --     LrDialogs.message("Publish complete", "All matching photos exported.")
    -- end

end)
