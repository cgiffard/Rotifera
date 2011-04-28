#!/usr/bin/perl

# Rotifera 0.1
# Christopher Giffard, 2011.
# http://www.github.com/cgiffard/Rotifera

use strict;

package tokeniser;

use constant NOT_EXPECTING => 0;
use constant EXPECTING_PROPERTYNAME => 1;
use constant EXPECTING_VALUE => 2;

sub go {
	my $RTFData = $_[0];
	my @TokenStack;
	my $ByteOffset = 0;
	my $Buffer = "";
	my @TMPTokens;
	our @DocInfo = ();
	our @UserProps = ();
	our @DocpropertyFields = ();
	our @Hyperlinks = ();
	
	### Initial Document Parse
	if ($RTFData && length($RTFData) > 50) { # A reasonable expectation...
		while ($ByteOffset < length($RTFData)) {
			if (substr($RTFData,$ByteOffset,1) eq "{") {
				if (scalar(@TokenStack) > 0) {
					my @TmpTokens = split(/\s*(\\[^\s\\]+|\\{2}\*\s+MERGEFORMAT)\s*/ig,$Buffer);
					@TmpTokens = grep(/[a-z0-9\/\.\;]/i,@TmpTokens);
					
					if (scalar(@TmpTokens)) {
						push(@{$TokenStack[scalar(@TokenStack)-1]},@TmpTokens);
					}
					$Buffer = "";
				}
				
				push(@TokenStack,[]);
			} elsif (substr($RTFData,$ByteOffset,1) eq "}") {
				if (scalar(@TokenStack) > 0) {
					my @TmpTokens = split(/\s*(\\[^\s\\]+|\\{2}\*\s+MERGEFORMAT)\s*/ig,$Buffer);
					@TmpTokens = grep(/[a-z0-9\/\.\;]/i,@TmpTokens);
					
					if (scalar(@TmpTokens)) {
						push(@{$TokenStack[scalar(@TokenStack)-1]},@TmpTokens);
					}
					
					# Now fix heirarchy
					if (scalar(@TokenStack) > 1) {
						push(@{$TokenStack[scalar(@TokenStack)-2]},pop(@TokenStack));
					}
					
					$Buffer = "";
				}
				
			} else {
				$Buffer .= substr($RTFData,$ByteOffset,1);
			}
			
			$ByteOffset ++;
		}
		
	} else {
		die("Couldn't tokenise provided data!");
	}
	
	sub processUserProperties {
		if (ref($_[0]) eq "ARRAY") {
			my @TokenArray = @{$_[0]};
			my $Mode = NOT_EXPECTING;
			my $CurrentPropertyName = "";
			my $CurrentPropertyType = 0;
			my $CurrentPropertyValue = "";
			
			foreach my $PropertyKey (@TokenArray) {
				next if $PropertyKey eq "\\userprops";
				
				if (ref($PropertyKey) eq "ARRAY" && $Mode == NOT_EXPECTING) {
					if ((@{$PropertyKey})[0] eq "\\propname") {
						$CurrentPropertyName = (@{$PropertyKey})[1];
						$CurrentPropertyName =~ s/^\s+|\s+$//ig;
						$CurrentPropertyName =~ s/[\n\r]//ig;
						$Mode = EXPECTING_VALUE;
					}
				} elsif ($PropertyKey =~ m/^\\proptype/i && $Mode == EXPECTING_VALUE) {
					$CurrentPropertyType = int(pop(@{[split(/proptype/,$PropertyKey)]}));
					next;
				} elsif ($Mode == EXPECTING_VALUE) {
					if ($CurrentPropertyType > 0) {
						if (ref($PropertyKey) eq "ARRAY") {
							if ((@{$PropertyKey})[0] eq "\\staticval") {
								$CurrentPropertyValue = (@{$PropertyKey})[1];
								if ($CurrentPropertyValue != 30) {
									$CurrentPropertyValue =~ s/[\n\r]//ig;
								}
								
								push(@UserProps,{
									"name" => $CurrentPropertyName,
									"value" => $CurrentPropertyValue,
									"type" => $CurrentPropertyType
								});
								
								$CurrentPropertyName = "";
								$CurrentPropertyType = 0;
								$CurrentPropertyValue = "";
								$Mode = NOT_EXPECTING;
							} else {
								print STDERR "WARNING: Non-static/linked property values aren't yet supported.\n";
							}
						} else {
							print STDERR "SERIOUS ERROR: Out of order property descriptors when processing \\userprops block: Saw non-array ref when expecting one.\n";
						}
					} else {
						print STDERR "SERIOUS ERROR: Out of order property descriptors when processing \\userprops block: Didn't know the current property type.\n";
					}
				
					$CurrentPropertyType = 0;
					$Mode = NOT_EXPECTING;
				} else {
					print STDERR "SERIOUS ERROR: Out of order property descriptors when processing \\userprops block: Caught trap when parsing.\n";
				}
			}
		}
	}
	
	sub processDocumentInformation {
		if (ref($_[0]) eq "ARRAY") {
			my @TokenArray = @{$_[0]};
			my %DocInfoTokens = (
				"title"		=> "Title",
				"subject"	=> "Subject",
				"author"	=> "Author",
				"manager"	=> "Manager",
				"company"	=> "Company",
				"operator"	=> "Operator",
				"category"	=> "Category",
				"keywords"	=> "Keywords",
				"comment"	=> "Comment",
				"doccomm"	=> "Document Comments",
				"hlinkbase"	=> "Hyperlink Base",
				"creatim"	=> "RTF Create Time",
				"revtim"	=> "RTF Revision Time",
				"printim"	=> "RTF Print Time",
				"buptim"	=> "RTF Backup Time",
				"time"		=> "RTF Time",
				"vern"		=> "RTF Version Number",
				"edmins"	=> "Editing Time In Minutes",
				"yr"		=> "Year",
				"mo"		=> "Month",
				"dy"		=> "Day",
				"hr"		=> "Hour",
				"min"		=> "Min",
				"sec"		=> "Sec",
				"nofpages"	=> "Number of Pages",
				"nofchars"	=> "Number of Characters",
				"nofcharsws"=> "Number of Characters With Spaces",
				"nofwords"	=> "Number of Words",
				"version"	=> "Version",
				"id"		=> "RTF ID"
			);
		
			if ($TokenArray[0]  eq "\\info") {
				for my $DocumentInfoKey (@TokenArray) {
					if (ref($DocumentInfoKey) eq "ARRAY") {
						my @DocumentInfoKey = @{$DocumentInfoKey};
						my $DocumentInfoKeyName = $DocumentInfoKey[0];
						my $DocumentInfoKeyValue = "";
						$DocumentInfoKeyName =~ s/^\\//;
						chomp $DocumentInfoKeyName;
					
						if (scalar(@DocumentInfoKey) == 1 && $DocumentInfoKeyName =~ m/\d/g) {
							my @KeyParts = split(/(\d+)/g,$DocumentInfoKeyName);
							$DocumentInfoKeyName = shift(@KeyParts);
							push(@DocumentInfoKey,@KeyParts);
						}
						
						if (exists $DocInfoTokens{$DocumentInfoKeyName}) {
							$DocumentInfoKeyName = $DocInfoTokens{$DocumentInfoKeyName};
						}
					
						if (scalar(@DocumentInfoKey) <= 1) {
							# If, after preprocessing for values which appear as part of the key name as a pair (like \edmins3,)
							# we still only have one (or no) items, we'll set this to undef.
							$DocumentInfoKeyValue = undef;
						} elsif (scalar(@DocumentInfoKey) == 2) {
							$DocumentInfoKeyValue = $DocumentInfoKey[1];
						} else {
							# To do: be bothered to use native date functions & parse properly accounting for different formats,
							# timezone etc.
							my $YearValue		= join("",split(/^\\yr/,shift(@{[grep(/^\\yr/,@DocumentInfoKey)]})));
							my $MonthValue		= join("",split(/^\\mo/,shift(@{[grep(/^\\mo/,@DocumentInfoKey)]})));
							my $DayValue		= join("",split(/^\\dy/,shift(@{[grep(/^\\dy/,@DocumentInfoKey)]})));
							my $HoursValue		= join("",split(/^\\hr/,shift(@{[grep(/^\\hr/,@DocumentInfoKey)]})));
							my $MinutesValue	= join("",split(/^\\min/,shift(@{[grep(/^\\min/,@DocumentInfoKey)]})));
							my $SecondsValue	= join("",split(/^\\sec/,shift(@{[grep(/^\\sec/,@DocumentInfoKey)]})));
						
							$DocumentInfoKeyValue = $DayValue."/".$MonthValue."/".$YearValue." ".$HoursValue.":".$MinutesValue;
						}
					
						push(@DocInfo, {
							"name"	=> $DocumentInfoKeyName,
							"value"	=> $DocumentInfoKeyValue
						});
					}
				};
			}
		}
	}
	
	sub processTokens {
		my @TokenArray = @{$_[0]};
		for my $TokenItem (@TokenArray) {
			if ($TokenItem eq"\\field") {
				if (getTextForToken($TokenArray[1]) =~ m/^DOCPROPERTY/i) {
					my $DocpropertyName = getTextForToken($TokenArray[1]);
					# Pull off DOCPROPERTY word at beginning of string
					$DocpropertyName = pop(@{[split(/\s+\"*/, $DocpropertyName, 2)]});
					# Pull off pesky MERGEFORMAT stuff if by chance it escapes the parser
					# due to mal-formedness
					$DocpropertyName = shift(@{[split(/\\/g, $DocpropertyName, 2)]});
					# Final Clean
					$DocpropertyName =~ s/[\"\s]+$//ig;
					chomp $DocpropertyName;
					
					my $DocpropertyValue = getTextForToken($TokenArray[2]);
					$DocpropertyValue =~ s/[\"\s]+$//ig;
					
					push(@DocpropertyFields, {
						"name"	=> $DocpropertyName,
						"value"	=> $DocpropertyValue
					});
				}
				return;
			} elsif ($TokenItem eq "\\userprops") {
				processUserProperties(\@TokenArray);
				return;
			} elsif ($TokenItem eq "\\info") {
				processDocumentInformation(\@TokenArray);
				return;
			} else {
				if (ref($TokenItem) eq "ARRAY") {
					processTokens($TokenItem);
				}
			}
		}
	}
	
	processTokens(\@TokenStack);
	$tokeniser::DOCPROPERTYFields = \@DocpropertyFields;
	$tokeniser::UserProps = \@UserProps;
	$tokeniser::DocInfo = \@DocInfo;
}

sub getTextForToken {
	my @TokenList, my @TmpInternalList;
	@TokenList = @{$_[0]} if ref($_[0]) eq "ARRAY";
	
	# Get text out of subtokens
	for (0 ...  scalar(@TokenList)) {
		if (ref($TokenList[$_]) eq "ARRAY") {
			push(@TmpInternalList,getTextForToken($TokenList[$_]));
		} else {
			push(@TmpInternalList,$TokenList[$_]);
		}
	}
	
	@TmpInternalList = grep(!/^\\/,@TmpInternalList);
	return join("",@TmpInternalList);
}

################################## END
1;