# About Rotifera

Rotifera (from RTF) is a very straightforward tool to extract metadata from RTF files, validate it, and report on errors. It currently supports extraction/inspection of:

* DOCPROPERTY Fields
* User Document Properties
* Document Info

It will soon also extract:

* Bookmarks
* Linked Values (provided I can find some test files which actually do this!)
* List of Hyperlinks

Rotifera will validate your documents against a schema which you can extend to include your own corporate or personal metadata, and supports required data, allowed values, datatypes etc. Apart from JSON.pm it has no dependencies.

# Using Rotifera

It doesn't get simpler than this:

	./rotifera.pl myfile.rtf
	./rotifera.pl docs/*.rtf

Rotifera has a bunch of options you can use to have loads of fun:

* `-schema`
	
	Validates against the supplied schema in schema.pl.
* `-json`
	
	Outputs the gathered metadata in JSON format.
* `-printtable`
	
	Pretty-prints a table with the gathered metadata.
* `-silent`
	
	Suppresses all informational and warning messages, displaying only extreme fatal errors.
* `-die`
	
	Cancels execution on first schema or data extraction error.
* `-nocolour`
	
	Outputs as plain text with no colour instructions.
* `-listfaileddocs`
	
	Lists all the documents which failed schema validation/metadata extraction after processing.
	
Combine these options for hilarious effects:

	./rotifera.pl -printtable -json -schema mydoc.rtf docs/*.rtf

Alternately, you can use the very limited API:

	require "tokeniser.pl";
	$tokeniser::go($RTFData); # The tokeniser won't read the files for you. You'll need to do that yourself!
	
	# Voila! Metadata!
	$tokeniser::DOCPROPERTYFields;
	$tokeniser::UserProps;
	$tokeniser::DocInfo;
	
You can find schema editing instructions in the schema file itself.

# Licence

You may copy and use this library as you see fit (including commercial use) and modify it, as long as you retain my attribution comment (which includes my name, link to this github page, and library version) at the top of all script files. You may not, under any circumstances, claim you wrote this library, or remove my attribution. (Fair's fair!)

I'd appreciate it if you'd contribute patches back, but you don't have to.