local LrFunctionContext = import 'LrFunctionContext'
local LrTasks = import 'LrTasks'
local LrApplication = import 'LrApplication'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrView = import 'LrView'
local LrTasks = import 'LrTasks'
local LrPathUtils = import 'LrPathUtils'

-- Write trace information to the logger.
local LrLogger = import 'LrLogger'
local myLogger = LrLogger( 'logPhotoListToCollection' )
myLogger:enable( "logfile" ) -- Pass either a string or a table of actions
local function Log( message )
	myLogger:trace( message )
end

Log('=============== Started ====================')
local catalog = LrApplication.activeCatalog()

function showImportDialog( context )
	LrDialogs.attachErrorDialogToFunctionContext( context )
	
	local props = LrBinding.makePropertyTable( context ) -- create bound table
	props.selectedCollection = nil;
	local selectedCollection = nil
	for i,c in pairs(catalog:getActiveSources()) do
		if c:type() == 'LrCollection' then
			selectedCollection = c
			props.selectedCollection = c.localIdentifier
			break;
		end
	end
	
	props.collectionItems = {}
	for i, c in pairs(catalog:getChildCollections()) do
		table.insert(props.collectionItems, {title = c:getName(), value = c.localIdentifier})
		if c.localIdentifier == props.selectedCollection then
			selectedCollection = nil
		end
	end
	if selectedCollection then
		table.insert(props.collectionItems, {title = selectedCollection:getName(), value = selectedCollection.localIdentifier})
	end
	
	local bind = LrView.bind;
	local f = LrView.osFactory()
	local contents = f:column{
		bind_to_object = props,  -- bound to our data table
		spacing = f:control_spacing(),
		width = 400,
		f:row{
			f:static_text{
				fill = 0.4,
				title = 'Select source files'
			},
			f:row{
				fill = 0.6,
				f:edit_field{
					fill_horizontal = 1,
					enabled = false,
					value = bind 'selectedFilesStr',
				},
				f:push_button{
					title = "...",
					action = function() selectFileNames(props) end,
				},
			},
		},
		f:row{
			f:static_text{
				fill = 0.4,
				title = 'Select target collection'
			},
			f:popup_menu{
				fill = 0.6,
				items = props.collectionItems,
				value = bind('selectedCollection'),
			},
		},
		f:row{
			f:column{
				spacing = f:control_spacing(),
				f:separator{
					fill_horizontal = 1,
				},
				-- f:static_text{
					-- title = 'Found in catalog'
				-- },
				f:simple_list{
					items = bind 'selectedPhotos',
					--allows_multiple_selection = true
				},
			}
		}
	}
	
	while true do
		local result = LrDialogs.presentModalDialog(
			{
				title = 'Add photos',
				contents = contents,
				actionBinding = 'ok',
			}
		)
		
		if result ~= 'ok' then
			return
		end
		
		if not props.selectedFiles then
			LrDialogs.message("No source photo list was selected", nil, 'critical')
		elseif not props.selectedCollection then
			LrDialogs.message("No target collection was selected", nil, 'critical')
		else
			RunImport(props.selectedFiles, props.selectedCollection)
			break
		end
	end
	
end

function selectFileNames(props)
	props.selectedFiles = nil
	props.selectedFilesStr = ""
	props.selectedPhotos = nil
	local selectedFiles = LrDialogs.runOpenPanel(
		{
			canChooseFiles = true,
			allowsMultipleSelection = true,
		}
	)
	if (selectedFiles) then
		selectedFiles = getFileNames(selectedFiles)
		local setOfNames = tableToSet(selectedFiles)
		props.selectedFiles = tableKeysToArray(setOfNames)
		props.selectedFilesStr = table.concat(props.selectedFiles, ", ")
		LrTasks.startAsyncTask(function()
			local selectedPhotos = {}
			local photos = findPhotosInCatalog(props.selectedFiles)
			if (#photos.notFound > 0) then
				table.insert(selectedPhotos, {title = 'Not found in catalog', value = 'found'})
				for k,f in pairs(photos.notFound) do
					table.insert(selectedPhotos, {title = f, value = f})
				end
				table.insert(selectedPhotos, {title = '-------', value = '-'})
			end
			if #photos.found > 0 then
				table.insert(selectedPhotos, {title = 'Found in catalog', value = 'found'})
				for k,f in pairs(photos.found) do
					local name = f:getFormattedMetadata("fileName")
					local copyName = f:getFormattedMetadata("copyName")
					if copyName then
						name = name..", "..copyName
					end
					local folderName = f:getFormattedMetadata("folderName")
					name = folderName..'\\'..name
					table.insert(selectedPhotos, {title = name, value = f.localIdentifier})
				end
			end
			props.selectedPhotos = selectedPhotos
		end)
	end
end
					
function getFileNames(selectedFiles)
	local fileNames = {}
	if selectedFiles then
		for i,f in pairs(selectedFiles) do
			local n = LrPathUtils.leafName(f)
			n = LrPathUtils.removeExtension(n)
			table.insert(fileNames, n:lower())
		end
	end
	return fileNames
end

function tableKeysToArray(sourceTable)
	local result = {}
	if sourceTable then
		for k,v in pairs(sourceTable) do
			table.insert(result, k)
		end
	end
	return result
end

function tableToSet(sourceTable)
	local resultSet = {}
	if sourceTable then
		for k,v in pairs(sourceTable) do
			resultSet[v] = true
		end
	end
	return resultSet
end

function findPhotosInCatalog(selectedFiles)
	Log('findPhotosInCatalog')
	local setOfNames = tableToSet(selectedFiles)
	local notFoundNames = tableToSet(selectedFiles)
	Log('N='..#selectedFiles)
	local allFotos = catalog:getAllPhotos()
	Log('NF='..#allFotos)
	local result = {}
	for i,f in pairs(allFotos) do
		local name = f:getFormattedMetadata("fileName")
		name = LrPathUtils.removeExtension(name)
		if setOfNames[name:lower()] then
			Log("File: "..name)
			table.insert(result, f)
			notFoundNames[name:lower()] = nil
		end
	end
	return {found = result, notFound = tableKeysToArray(notFoundNames)};
end

function RunImport(selectedFiles, selectedCollection)
	local photosToAdd = findPhotosInCatalog(selectedFiles).found
	local collection = catalog:getCollectionByLocalIdentifier(selectedCollection)
	catalog:setActiveSources({collection});
	if #photosToAdd > 0 then
		catalog:withWriteAccessDo("Import photo list", function()
			collection:addPhotos(photosToAdd)
			local firstPhoto = photosToAdd[1];
			table.remove(photosToAdd, 1)
			catalog:setSelectedPhotos(firstPhoto, photosToAdd)
		end)
	end
end


LrFunctionContext.postAsyncTaskWithContext( "showImportDialog", showImportDialog)
