#!/usr/bin/env perl

use v5.16;

package Filenamer;

use strict;
use warnings;

#
#  Tries to takes @ARGV and condense it into a shortish string
#  Example:  ./myscript.pl file1.txt file2.txt file3.txt would be condensed to
#	file1__2__3.txt
#	
sub condense_argv
{
	my $args = [@ARGV];
	my @fn = (shift @$args);
	return $fn[0] unless scalar @$args;
	my @first_letters = split '',$fn[0];
	my $first_letters_len = scalar @first_letters;
	my($first_ext) = $fn[0] =~ m/(\.[^\.]+)$/;
	my $qr_first_ext = defined $first_ext ? qr/$first_ext/ : undef;
	$fn[0] =~ s/$first_ext//g if defined $first_ext;
	my %qs;
	for my $arg (@$args)
	{	
		my $idx = 0;
		my $i = 0;
		for(split //,$arg)
		{
			if($i < $first_letters_len)
			{
				if( $first_letters[$i] ne $_)
				{
					$idx  = $i;
					last;
				}
				$i++;
			}
		}
		$arg = substr $arg,$idx if $idx > 0;
		$arg =~ s/$first_ext$// if defined $qr_first_ext and $arg =~ $qr_first_ext;
		push @fn,$arg;
	}
	my $final_fn = join('__',@fn); ## no file extension on return value . $first_ext;
	$final_fn =~ s/[^0-9A-Za-z\.\,\-\_]/--/g;
	$final_fn
}


package main; 
 
use strict;
use warnings;

our $qr_subj_verb = qr/^\s*([^,]+)\s+(is\s+excluded)\s*$/;
our $qr_subj_verb_obj = qr/^\s*([^,]+)\s+(equals|contains|is|blast)\s+([^,]+)\s*$/;
our $qr_or_delimiter = qr/\s+or\s+/;

my $results = {};
my $queries_file = &Filenamer::condense_argv;
open my $queries_fh, ">$queries_file.queries" or die "Can't create $queries_file.queries, $!\n";
for(@ARGV)
{
	open my $fh, "<$_" or die "Can't read $_, $!\n";
	<$fh>; # read past first line, which is a line of column names, not data
	while(<$fh>)
	{
		my $q = &getQueryField($_);
		next unless $q;
		&logQuery($q);
		my $res = &parseQuery($q);
		&addResult($res) if defined $res;
	}
}

exit;

sub getQueryField
{
	my $data = shift;
	return unless defined $data;
	chomp $data;
	my($f0,$f1,$f2,$f3,$f4,$f5,@f6) = split /[|]/,$data;
	my $query = join '',@f6;

	## deal with query having | chars in it, ie entire field isn't quoted if it contains the delimiter character
	my $yes_no_idx = 0;
	for(@f6)
	{
		last if /^\s*(?:yes|no)\s*$/;
		$yes_no_idx++;
	}

	$query = join '|',(map{$f6[$_]}0..($yes_no_idx-2)) if $yes_no_idx != 0;
	return if $query =~  /^\s*$/;

	$query =~ s/^\s+//;
	$query =~ s/\s+$//;
	$query
}

sub logQuery
{
	my $fh = shift;
	my $data = shift;
	return unless defined $data;
	chomp $data;
	print $fh $data,"\n";
}
 
sub parseQuery
{
	my $query = shift;
	return unless defined $query;

	my $matches = [];
	my $has_multiselect = 0;

	## getting complex, we have multi-select queries, so that's multiple [subject|verb|[object]]+ separated by , or 'or'
	unless( &_find_subquery($query,$matches) )
	{
		# split on ',' first, 'or' second and see if any subqueries fail a  subj|verb|(obj)* match
		for( split /,/,$query)
		{
			if( $_ =~ $qr_or_delimiter )
			{
				my $submatches = [];
				&_find_subquery($_,$submatches) for split $qr_or_delimiter,$_;
				if(scalar(@$submatches) > 0)
				{
					$has_multiselect = 1 unless $has_multiselect;
					push @$matches,$submatches 
				}
			}
			else
			{
				&_find_subquery($_,$matches);
			}
		}
	}
	return { query => $query, matches =>$matches, has_multiselect => $has_multiselect };
}

sub _find_subquery
{
	my($query,$matches) = @_;
	my @subquery_matches;

   ## simple match, subject verb
	if(@subquery_matches = $query =~ m/$qr_subj_verb/)
   {
      #print "subj verb matches: @matches from $query\n";
      push @$matches,[@subquery_matches];
		return 1;
   }
   ## simple match, subject verb object
   elsif( $query !~ $qr_or_delimiter and (@subquery_matches = $query =~ m/$qr_subj_verb_obj/))
   {
      push @$matches,[@subquery_matches];
		return 1;
   }
}
 
sub addResult
{
	my $this = shift;
	my $data = shift;
	return unless defined $data;
	my $query = $data->{query};
	my $matches = $data->{matches};
	#print "query $query\n";
	$results->{has_multiselect} ++ if $data->{has_multiselect};
	#print "has multiselect? ", (exists $data->{has_multiselect} and $data->{has_multiselect} ? 'y' : 'n') ,"\n";
	for(@$matches)
	{
		unless(ref $_ eq 'ARRAY' && ref $_->[0] eq 'ARRAY')
		{
			&_count_query($_);
			next;
		}
		my $subj_seen = {};
		my $verb_seen = {};
		my $obj_seen = {};
		&_count_query($_,$subj_seen,$verb_seen,$obj_seen) for @$_;
	}
}

sub _count_query
{
	my($q,$subj_seen,$verb_seen,$obj_seen) = @_;
	my $subj = $q->[0];
	my $verb = $q->[1];
	my $obj = scalar(@$q) > 2 ? $q->[2] : undef;
	if(defined $subj_seen && defined $verb_seen && defined $obj_seen)
	{
		unless(exists $subj_seen->{$subj})
		{
			$subj_seen->{$subj} = 1;
			$results->{"subject\t$subj"}++;
			$results->{"multiselect_subject\t$subj"}++;
		}
		unless(exists $verb_seen->{$verb})
		{
			$verb_seen->{$verb} = 1;
			$results->{"verb\t$verb"}++;
			$results->{"multiselect_verb\t$verb"}++;
		}
		if(defined $obj)
		{
			unless(exists $obj_seen->{$obj})
			{
				$obj_seen->{$obj} = 1;
				$results->{"object\t$obj"}++;
				$results->{"multiselect_object\t$obj"}++;
			}
		}
	}
	else
	{
		$results->{"subject\t$subj"}++;
		$results->{"verb\t$verb"}++;
		$results->{"object\t$obj"}++ if defined $obj;
	}
}


sub report
{
	my $this = shift;
	my $opt_fh = shift;
	if(defined $opt_fh)
	{
		print $opt_fh "$_\t$results->{$_}\n" for sort {$results->{$b} <=> $results->{$a} } keys %$results;
	}
	else
	{
		print "$_\t$results->{$_}\n" for sort {$results->{$b} <=> $results->{$a} } keys %$results;
	}
}

