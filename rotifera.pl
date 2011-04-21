#!/usr/bin/perl

# Rotifera 0.1
# Christopher Giffard, 2011.
# http://www.github.com/cgiffard/Rotifera

use strict;
use JSON;

my $FileData;
my $TaglessFileData;
my $FileBuffer;
my @MetadataUnclean;
my %MetadataClean;
my $CurrentPropertyName;
my $CurrentPropertyValue;

##### Command line options
our $RTFFilePath				= pop(@{[grep(!/^\-/,@ARGV)]});				# The RTF Filename!
our $Option_ValidateSchema		= scalar(grep(/\-schema/, @ARGV)) > 0;		# Determines whether a schema validation ocurrs
our $Option_OutputJSON			= scalar(grep(/\-json/, @ARGV)) > 0;		# Determines whether JSON is output
our $Option_OutputTable			= scalar(grep(/\-printtable/, @ARGV)) > 0;	# Determines whether a table of output is printed
our $Option_Silent				= scalar(grep(/\-silent/, @ARGV)) > 0;		# Silent operation (won't warn or error about anything)
our $Option_DieIfSchemaFailed	= scalar(grep(/\-die/, @ARGV)) > 0;			# Die on schema errors
#####

sub printUsage {
	if (!$Option_Silent && interactive()) {
		print blue()."Usage: ".creset().white().$0.creset()." [options] filename\n";
		print blue()."Available options:".creset()."\n";
		print "\t-schema      Validates against the supplied schema in schema.pl.\n";
		print "\t-json        Outputs the gathered metadata in JSON format.\n";
		print "\t-printtable  Pretty-prints a table with the gathered metadata.\n";
		print "\t-silent      Suppresses all informational and warning messages, displaying only extreme fatal errors.\n";
		print "\t-die         Cancels execution on first schema or data extraction error.\n\n";
	}
}

use constant NOT_EXPECTING => 0;
use constant EXPECTING_PROPERTYNAME => 1;
use constant EXPECTING_VALUE => 2;

my @RotiferaDirectory = split(/[\/\\]+/g,$0); pop(@RotiferaDirectory);
my $RotiferaDirectory = join("/",@RotiferaDirectory);

require $RotiferaDirectory."/tokeniser.pl";	# Reads RTF files, converts to parse tree (hopefully) without breaking!
require $RotiferaDirectory."/schema.pl";	# Schema for checking metadata values

### Colours!!!
# Shamelessly ripped off the homebrew install script http://mxcl.github.com/homebrew/
sub interactive		{	return -t STDIN && -t STDOUT;									}
sub blue			{	return bold(34)				if interactive && !$Option_Silent;	}
sub white			{	return bold(39)				if interactive && !$Option_Silent;	}
sub red				{	return underline(31)		if interactive && !$Option_Silent;	}
sub creset			{	return escape(0)			if interactive && !$Option_Silent;	}
sub bold			{	return escape("1;".$_[0])	if interactive && !$Option_Silent;	}
sub underline		{	return escape("4;".$_[0])	if interactive && !$Option_Silent;	}
sub escape			{	return "\033[".$_[0]."m"	if interactive && !$Option_Silent;	}

sub fatal {
	print STDERR red()."FATAL: ".$_[0].creset()."\n" if !$Option_Silent;
}

sub warning {
	print STDERR red()."WARNING:".creset()." ".$_[0]."\n" if !$Option_Silent;
	
	if ($Option_DieIfSchemaFailed) {
		die(red()."FATAL:".creset()." Dying on schema failure!\n");
	}
}

sub info {
	print blue()."INFO:".creset()." ".$_[0]."\n" if !$Option_Silent;
}

sub trim {
	my $InternalValue = $_[0];
	$InternalValue =~ s/^\s+//ig;
	$InternalValue =~ s/\s+$//ig;
	return $InternalValue;
}

sub homogeniseKeyName {
	my $KeyName = $_[0];
	
	if ($schema::keyformat eq "spaced") {
		$KeyName =~ s/(?<=[a-z0-9])([A-Z])/ $1/g;
		$KeyName =~ s/\b(\w+)\b/ucfirst($1)/ge;
	} else {
		$KeyName =~ s/\b(\w+)\b/ucfirst($1)/ge;
		$KeyName =~ s/\s//ig;
	}
	
	return $KeyName;
}

sub checkValueAgainstSchema {
	my $KeyName = $_[0];
	my $ValueToCheck = $_[1];
	
	if ($schema::rules{$KeyName}) {
		my %CurrentRuleset = %{$schema::rules{$KeyName}};
		
		if ($CurrentRuleset{"type"} eq "text") {
			if (defined $CurrentRuleset{"maxlength"}) {
				if (length($ValueToCheck) > $CurrentRuleset{"maxlength"}) {
					warning("\tThe value '".blue().$ValueToCheck.creset()."' for field '".blue().$KeyName.creset()."' was longer than the schema specified maximum of '".$CurrentRuleset{"maxlength"}."'.")
				}
			}
			
			if (defined $CurrentRuleset{"values"} && ref($CurrentRuleset{"values"}) eq "ARRAY") {
				my @AllowedValues = @{$CurrentRuleset{"values"}};
				
				if (!grep($_ eq $ValueToCheck,@AllowedValues)) {
					warning("\tThe value '".blue().$ValueToCheck.creset()."' for field '".blue().$KeyName.creset()."' was not found in the list of schema allowed values.");
				}
			}
		} elsif ($CurrentRuleset{"type"} eq "multi") {
			if (defined $CurrentRuleset{"values"} && ref($CurrentRuleset{"values"}) eq "ARRAY") {
				my @AllowedValues = @{$CurrentRuleset{"values"}};
				my @ValuesToCheck = split($schema::delimiter,$ValueToCheck);
				
				if (scalar(@ValuesToCheck)) {
					foreach my $CurrentSubValue (@ValuesToCheck) {
						$CurrentSubValue = trim($CurrentSubValue);
						if (!grep($CurrentSubValue,@AllowedValues)) {
							warning("\tThe value '".blue().$CurrentSubValue.creset()."' (of multiple values) for field '".blue().$KeyName.creset()."' was not found in the list of schema allowed values.");
						}
					}
				} else {
					if ($CurrentRuleset{"mandatory"}) {
						warning("\tThe mandatory multi-select field '".blue().$KeyName.creset()."' did not have a specified value.");
					}
				}
			}
		} elsif ($CurrentRuleset{"type"} eq "date") {
			
		} elsif ($CurrentRuleset{"type"} eq "int") {
			if (defined $CurrentRuleset{"maxlength"}) {
				if (length($ValueToCheck) > $CurrentRuleset{"maxlength"}) {
					warning("\tThe value '".blue().$ValueToCheck.creset()."' for field '".blue().$KeyName.creset()."' was longer than the schema specified maximum of '".$CurrentRuleset{"maxlength"}."'.")
				}
			}
		}
	} else {
		return 0;
	}
}

# Expects a simple key/value hash
sub printTable {
	my %TableHash = %{$_[0]};
	my $LongestKeyString = 10; # Minimum Length
	my $LongestValueString = 10; # Minimum Length
	my $PropertyKey;
	my $PropertyValue;
	my $TableWidth = 0;
	
	# Find Longest Key & Value Strings for Sizing Table
	
	foreach $PropertyKey (keys %TableHash) {
		if (length($PropertyKey) > $LongestKeyString) {
			$LongestKeyString = length($PropertyKey);
		}
	}
	$LongestKeyString += 2;
	
	foreach $PropertyValue (%TableHash) {
		my $PropertyValueLength = 0;
		if (ref($PropertyValue) eq "ARRAY") {
			$PropertyValueLength = 53;
		} else {
			$PropertyValue =~ s/[\n\r]//ig; #Kill Line Breaks
			$PropertyValueLength = length($PropertyValue);
		}
		
		if ($PropertyValueLength > $LongestValueString) {
			$LongestValueString = $PropertyValueLength;
		}
	}
	$LongestValueString += 2;
	
	# Print Table Header
	$TableWidth = (5 + ($LongestKeyString-4) + 7 + ($LongestValueString-6) + 1);
	print "\n\n".blue()."┏"."━"x($TableWidth-2)."┓\n";
	print blue()."┃ ".creset()."Key".(" "x($LongestKeyString-4)).blue()."│ ".creset()."Value".(" "x($LongestValueString-6)).blue()."┃\n";
	print "┗"."━"x($TableWidth-2)."┛\n".creset();
	
	# Print Rows
	foreach $PropertyKey (sort keys %TableHash) {
		$PropertyValue = $TableHash{$PropertyKey};
		
		if (ref($PropertyValue) eq "ARRAY") {
			print blue()."│ ".red().$PropertyKey.creset();
			print " "x($LongestKeyString - (length($PropertyKey)+1));
			print blue()."│ ".red()."WARNING:".creset()." ".blue()."Multiple values for this metadata property:".creset();
			print " "x($LongestValueString - 53);
			print blue()."│\n".creset();
			
			my $ValueCount = 1;
			foreach my $ArrayValue (@{$PropertyValue}) {
				$ArrayValue =~ s/[\n\r]//ig; #Kill Line Breaks
				print blue()."│ ";
				print " "x($LongestKeyString - (length($ValueCount.":")+1));
				print $ValueCount.":".creset();
				print blue()."│ ".creset().$ArrayValue;
				print " "x($LongestValueString - (length($ArrayValue) + 1));
				print blue()."│\n".creset();
				$ValueCount ++;
			}
		} else {
			$PropertyValue =~ s/[\n\r]//ig; #Kill Line Breaks
			
			print blue()."│ ".red().$PropertyKey.creset();
			print " "x($LongestKeyString - (length($PropertyKey)+1));
			print blue()."│ ".creset().$PropertyValue;
			print " "x($LongestValueString - (length($PropertyValue) + 1));
			print blue()."│\n".creset();
		}
	}
	
	print blue()."└"."─"x($LongestKeyString)."┴"."─"x($LongestValueString)."┘\n".creset()."\n\n";	
}

if (scalar(@ARGV) > 0 || length($RTFFilePath) > 0) {
	if (-e $RTFFilePath) {
		info("Opening file ".$RTFFilePath);
		
		if (open(RTFDATA,$RTFFilePath)) {
			binmode RTFDATA;
		
			info("Done. Extracting Metadata...");
			while (read(RTFDATA, $FileBuffer, 512)) {
				$FileData .= $FileBuffer;
			};
			close(RTFDATA);
		
			## Tokenise & Scan for Metadata...
			tokeniser::go($FileData);
			push(@MetadataUnclean,
					@{$tokeniser::DOCPROPERTYFields},
					@{$tokeniser::UserProps},
					@{$tokeniser::DocInfo}
				);
		
			foreach my $Property (@MetadataUnclean) {
				my $CurrentPropertyName = %{$Property}->{"name"};
				my $CurrentPropertyValue = %{$Property}->{"value"};
				my $DuplicateKeyFound = 0;
				my $DuplicateValueFound = 0;
			
				if (defined $MetadataClean{$CurrentPropertyName}) {
					warning("Duplicate metadata key ".white().$CurrentPropertyName.creset()." discovered in document.");
				}
			
				if (exists $schema::rules{$CurrentPropertyName}) {
					$schema::rules{$CurrentPropertyName}->{"found"} = 1;
				} elsif (exists $schema::rules{homogeniseKeyName($CurrentPropertyName)}) {
					warning("Metadata key ".white().$CurrentPropertyName.creset()." was not found in the schema. It was automatically corrected to ".white().homogeniseKeyName($CurrentPropertyName).creset().".");
					$CurrentPropertyName = homogeniseKeyName($CurrentPropertyName);
					$MetadataClean{$CurrentPropertyName} = "";
					$schema::rules{$CurrentPropertyName}->{"found"} = 1;
				} else {
					warning("Metadata key ".white().$CurrentPropertyName.creset()." was not found in the schema.");
				}
			
				if (ref($MetadataClean{$CurrentPropertyName}) eq "ARRAY") {
					$DuplicateKeyFound = 1;
					my @TmpValueArray = @{$MetadataClean{$CurrentPropertyName}};
				
					foreach my $CurrentValue (@TmpValueArray) {
						if ($CurrentValue eq trim($CurrentPropertyValue)) {
							$DuplicateValueFound = 1;
						}
					}
				
					if (!$DuplicateValueFound) {
						checkValueAgainstSchema($CurrentPropertyName,trim($CurrentPropertyValue));
						push(@TmpValueArray,trim($CurrentPropertyValue));
						$MetadataClean{$CurrentPropertyName} = \@TmpValueArray;
					}
				} else {
					checkValueAgainstSchema($CurrentPropertyName,trim($CurrentPropertyValue));
				
					if (length($MetadataClean{$CurrentPropertyName}) > 0) {
						$DuplicateKeyFound = 1;
						if (trim($CurrentPropertyValue) ne $MetadataClean{$CurrentPropertyName}) {
							my @TmpValueArray = ($MetadataClean{$CurrentPropertyName},trim($CurrentPropertyValue));
							$MetadataClean{$CurrentPropertyName} = \@TmpValueArray;
						} else {
							$DuplicateValueFound = 1;
						}
					} else {
						$MetadataClean{$CurrentPropertyName} = trim($CurrentPropertyValue);
					}
				}
			
				if ($DuplicateKeyFound) {
					if (!$DuplicateValueFound) {
						warning("\tThe duplicate metadata key ".white().$CurrentPropertyName.creset()." contains a new unrecognised value.");
					} else {
						info("\t\tThe duplicate metadata key ".white().$CurrentPropertyName.creset()." contains the same value as one or more of its predecessors.");
					}
				}
			
				$CurrentPropertyName = "";
			}
		
			info("Processed document to find ".scalar(keys(%MetadataClean))." valid metadata pairs.");
		
			for my $CurrentKey (keys %{$schema::rules}) {
				my %CurrentRuleset = %{$schema::rules{$CurrentKey}};
			
				if ($CurrentRuleset{"mandatory"} && !$CurrentRuleset{"found"}) {
					warning("The mandatory metadata key ".blue().$CurrentKey.creset()." was not found in the document!");
				}
			}
		
			printTable(\%MetadataClean) if $Option_OutputTable;
			info("JSON Object:") if $Option_OutputJSON && !$Option_Silent;
			print encode_json(\%MetadataClean)."\n\n" if $Option_OutputJSON;
		} else {
			fatal("Failed to Open File!");
			exit 1;
		}
	} else {
		fatal("The specified file does not exist!");
		printUsage();
	}
} else {
	fatal("No arguments supplied!");
	printUsage();
}