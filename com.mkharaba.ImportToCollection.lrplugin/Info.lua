return {
	LrSdkVersion = 5.0,
	LrSdkMinimumVersion = 5.0, -- minimum SDK version required by this plug-in
	LrToolkitIdentifier = 'com.MKharaba.PhotoListToCollection',
	LrPluginName = "Photo list importer",

	-- Add the menu item to the Library menu.
	LrLibraryMenuItems = {
		{
			title = "Add photos to collection...",
			file = "PhotoListToCollection.lua",
		},
	},
	VERSION = { major=1, minor=0, revision=0, build=12, },
}
