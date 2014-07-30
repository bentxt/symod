#!/usr/bin/perl
#
#
use warnings;
use strict;

use Data::Dumper;
use Scalar::Util 'looks_like_number';



(@ARGV)
    || die "Usage: modulate test.scm";

sub write_conf {
    my ($confname, $confdata) = @_;
    use JSON::XS;

    open my $fh, ">", $confname . '.out';
    print $fh encode_json($confdata);
    close $fh;
}

sub read_compconf {
    my ($confname ) = @_;
    use JSON::XS;
    my $json;
    {
      local $/; #Enable 'slurp' mode
      open my $fh, "<", $confname;
      $json = <$fh>;
      close $fh;
    }
    return decode_json($json);
}

sub addbuf {
    my ($lnbuf, $wordbuf, $intxt, $aliases, $modules, $globals, $builtins, $nsmod) = @_;

    return sub {
        my ($ch)  = shift;

        my $word = join '', @$wordbuf if @$wordbuf;
        undef @$wordbuf;
        if($word){
            if($word =~ /\./){
                my (@parts) = split /\./, $word;
                my ($pkg, @rest) = (@parts > 1 )
                    ? @parts
                    : die "Error in qualified symbol $word"
                    ;
                my $rslv = $aliases->{$pkg};
                push @$lnbuf, ($rslv)
                    ? $rslv . '.' . (join '.', @rest) 
                    : die "Error in qualified symbol $word"
                    ;
            }elsif($word =~ /^\./){
                die "Err: dont start with a dot"
            }else{
                if( exists $globals->{$word}){
                    push @$lnbuf, $globals->{$word} 
                }elsif(exists $modules->{$word} ){
                    push @$lnbuf, $modules->{$word}; 
                }elsif( exists $builtins->{$word}){
                    push @$lnbuf, $word;
                }else{
                    push @$lnbuf, (looks_like_number($word))
                        ? $word
                        :  '.' . $nsmod . '.' . $word;
                }
            }
        };
    };
}

sub intxt {
    my ($lnbuf, $wordbuf, $intxt) = @_;

    return sub {
    if($_ eq '"'){
        push @$lnbuf, join '', (@$wordbuf, '"');
        undef @$wordbuf; undef ${$intxt};
    }else{
        push @$wordbuf, $_;
    }
    };
}

my %Rules = (
    '(' => '(',
    ')' => ')',
    '[' => '( list',
    ']' => ')',
    ' ' => ' ',
    "\n" => undef,
);

sub loopfile{
    my ($conf, $modfile, $module, $lines  ) = (@_);

    my (@lnbuf, @wordbuf, $intxt); 
    my $do_intxt = intxt(\@lnbuf, \@wordbuf, \$intxt);
    my $addbuf = addbuf(\@lnbuf, \@wordbuf, \$intxt, $conf->{aliases}, $conf->{modules}->{$module}, $conf->{globals}, $conf->{builtins}, $conf->{ns} . '.' . $module);

    my ($i, @filebuf) = (0); 
    foreach my $ln (@$lines){  $i++;
        undef @lnbuf;
        foreach (split '', $ln){
            if($intxt){
                $do_intxt->($_);
            }else{
                if ($_ eq '"'){;
                    $addbuf->() ;
                    push @wordbuf, '"';
                    $intxt = 1 ;
                }else{
                    if(exists $Rules{$_}){
                        $addbuf->($Rules{$_});
                        push @lnbuf, $_ if (defined $Rules{$_} );
                    }else  {
                        push @wordbuf, $_;
                    }
                } 
            } 
        }
        push @lnbuf, " ; #" . $i . "($modfile)" unless $intxt;
        (@lnbuf) && push @filebuf , join '',  @lnbuf;
        undef @lnbuf;
    }
    push @filebuf,  "\n";
    return \@filebuf;
}

sub compile_file{
    my ($build_cmd,  $build_file) = @_;
    

    system($build_cmd, "$build_file");

    if($? == -1){
            print "Error\n";
            print $!;
        }elsif($? == 0){
           
        }else{
            print $?;
        }
}

sub write_outfile{
    my ($conffile, $build_dir) = @_;
    my $confdata = read_compconf($conffile);


    my $list = join ' ', map { "$build_dir/$_" } @{ $confdata->{filelist} };
    system("cat $list");

}

sub compile_dir{
    my ($build_cmd, $build_dir, $exportlist ) = @_;

    my @files;
    foreach (@$exportlist){
        my ($k, $v) = %{$_};
        push @files, $k;
    }
    my $list = join ' ',  map { "$build_dir/$_" } @files;
    system("$build_cmd $list");

}

sub usage {
    print "usage: ...";
    exit;

}


    
sub conf_data{ 
    my ($conf, @pairs) = @_;

    my @rets;
    foreach (@pairs){
        my ($node, $type) = @{$_};

        #print 'nn ' . $conf->{$node};
        #print "\n";
        push @rets, (ref $conf->{$node} eq $type)
            ? $conf->{$node}
            : die "Err: no valid node $node"
            ;
    }
    return @rets;


}
sub do_ns{
    my ($conf, $conson, $moduletree, $nsname, $nsdata) = @_;
    my ($allimports, $allexports) = conf_data($nsdata, (
        [ imports => 'HASH' ],
        [ exports => 'HASH'],
    ));

    my $exports;
    foreach my $mod (keys %$allexports){
        my ($nsexps) = conf_data($allexports, ( 
                [ $mod, 'ARRAY']));

        my $module_exports = $moduletree->{$mod}->{exports};
        
        foreach my $e (@$nsexps){
            # TODO
            my $res = grep { $e eq $_ } @$module_exports;
            die "Err: ns import $e not exists" unless $res;
            $conson->{globals}{$nsname . '.' . $e} = $nsname . '.' . $e;
            $conson->{globals}{$nsname . '.' . $mod . '.' .  $e} = $nsname . '.' . $e;
            $conson->{globals}{$mod . '.' .  $e} = $nsname . '.' . $e;
            $conson->{globals}{$e} = $nsname . '.' . $e;
        }
    }

    foreach my $mod (keys %$allimports){
        my ($nsimps) = conf_data($allimports, ( 
                [ $mod, 'ARRAY']));

        foreach my $i (@$nsimps){
            # TODO import check
            #my $res = grep { $i eq $_ } @$modimp;
            #die "Err: ns import $i not exists" unless $res;

            $conson->{globals}{$nsname . '.' . $i} = $nsname . '.' . $i;
            $conson->{globals}{$i} = $nsname . '.' . $i;
        }
    }

    return $exports;
}

sub get_moduletree {
    my $modules = shift;
    my $moduletree; 
    my %filemap; my @filelist;
    my $i = 0;
    foreach (@$modules){
        die "Err: syntax error in Modules " unless ref $_ eq 'HASH';
        my ($file, $v) = %$_;
        my $module = $file;
        if( -f $file) {
            if(exists $filemap{$file}){
                die "Err: file already exist"
            }else{
                push @filelist, $file;
                $module = $file;
                $module =~ s/\..*$//;
                $filemap{$file} = $module;
            }
        }else{
            die "Err: file $module not exist";
        }

        my ($modimpexp) = conf_data ($_, (
            [ $file, 'HASH']));
        conf_data ($modimpexp, (
            [ exports => 'ARRAY']));
        conf_data ($modimpexp, (
            [ imports => 'HASH']));
            if(exists $moduletree->{$module}){
                die "Err: file already exist"
            }else{
                $moduletree->{$module} = $v;
            }
    }
    return ($moduletree, \@filelist, \%filemap);
}

sub do_modules{
    my ($conf, $conson, $moduletree, $nsname, $nsdata) = @_;
    
    $conson->{modules} = undef;

    foreach my $module (keys %$moduletree){

        my ($impexp) = $moduletree->{$module};
        my $exports = $impexp->{exports};
        foreach my $e (@$exports){
            if((split /\./, $e) >  1){ die "todooo" }
            $conson->{modules}->{$module}->{$e} = $nsname . '.' . $module . '.' . $e;
        }
        my $imports = $impexp->{imports};
        foreach my $impmodule (keys %{$imports}){
            my $importmods = $imports->{$impmodule};
            if(exists $moduletree->{$impmodule}){
                my $exps = $moduletree->{$impmodule}->{exports};
                foreach my $i (@$importmods){
                    my ($res) = grep{  $i eq $_ } @$exps;
                    die "Err: coulnd math import module" unless $res;
                    $conson->{globals}->{$i} = $nsname . '.' . $impmodule . '.' . $i;
                    if(exists $conson->{modules}->{$module}->{$i}){
                        die "Err: import already exists " 
                    }else{
                        $conson->{modules}->{$impmodule}->{$i} = $nsname . '.' . $impmodule . '.' .  $i;
                    }
                    #$conson->{globals}->{$nsname}->{$i} = $nsname . '.' . $impmodule . '.' . $i;
                }
            }else{
                die "Err: couldnt find import module $impmodule"
            }
       }
    }
}
sub compile_conf{
    my $confile = shift;
    my $conf = require $confile;
    my ($aliases, $modules, $ns) = conf_data($conf, (
        [ aliases => 'HASH'],
        [ modules => 'ARRAY' ],
        [ ns => 'HASH']
    ));

    my ($moduletree, $filelist, $filemap) = get_moduletree($modules);
    my $conson = {};
    $conson->{filelist} = $filelist;
    $conson->{filemap} = $filemap;

    my ($nsname, $nsdata) = %{$ns};
    $conson->{ns} = $nsname;
    die "Err: invalid nsdata " unless ref $nsdata eq 'HASH';

    my $exports = do_ns($conf, $conson,  $moduletree, $nsname, $nsdata);
    do_modules($conf, $conson, $moduletree, $nsname);

    $conson->{aliases} = $aliases; 

    $conson->{builtins} = internalize(); 
    write_conf($confile, $conson);
}


sub build_modulefile {
    my ($conffile, $modfile) = @_;

    my $confdata = read_compconf($conffile);

    my @nparts = split /\./, $modfile;

    my ($module) = (@nparts == 2)
        ? @nparts
        : die "Err Invalid filename";

    #my $solver = solver($module, $confdata);
    
    open (my $fh , '<', $modfile) || die "Err: Coulnd open file $modfile";
    my @lines = <$fh>;
    close $fh;

    my $filebuf = loopfile($confdata, $modfile, $module, \@lines ); 
    print join "\n", @$filebuf;
}
sub run_outdir{
}


sub main {
    my ($conf_file) = ( -f $ARGV[0] )
        ? ( $ARGV[0])
        : die "Err: no conf file"
        ;
        
    if(@ARGV == 1){
        compile_conf($conf_file);
    }elsif(@ARGV == 2){
        die "Err:  no conf file" unless -f $ARGV[0];
        if(-f $ARGV[1]){
            build_modulefile(@ARGV);
            exit;
        }elsif(-d $ARGV[1]){
            write_outfile(@ARGV);
            exit;
        }else{
            usage();
        }
    }elsif(@ARGV == 3){
        if(-f $ARGV[1]){
            run_outfile(@ARGV);
            exit;
        }elsif(-d $ARGV[1]){
            run_outdir(@ARGV);
            exit;
        }else{ 
            usage();
        }
    }else{
        usage();
    }
}




sub internalize {

my %interns = ( 

'&' => 1, '*' => 1, '+' => 1, '-' => 1, '-' => 1, '/' => 1, '/' => 1, '<' => 1, '<=' => 1, '=' => 1, '>' => 1, '>=' => 1, 'abs' => 1, 'acos' => 1, 'and' => 1, 'angle' => 1, 'append' => 1, 'append' => 1, 'apply' => 1, 'asin' => 1, 'assert' => 1, 'assertion-violation' => 1, 'assertion-violation?' => 1, 'assoc' => 1, 'assp' => 1, 'assq' => 1, 'assv' => 1, 'atan' => 1, 'atan' => 1, 'begin' => 1, 'binary-port?' => 1, 'bitwise-and' => 1, 'bitwise-arithmetic-shift' => 1, 'bitwise-arithmetic-shift-left' => 1, 'bitwise-arithmetic-shift-right' => 1, 'bitwise-bit-count' => 1, 'bitwise-bit-field' => 1, 'bitwise-bit-set?' => 1, 'bitwise-copy-bit' => 1, 'bitwise-copy-bit-field' => 1, 'bitwise-first-bit-set' => 1, 'bitwise-if' => 1, 'bitwise-ior' => 1, 'bitwise-length' => 1, 'bitwise-not' => 1, 'bitwise-reverse-bit-field' => 1, 'bitwise-rotate-bit-field' => 1, 'bitwise-xor' => 1, 'boolean=?' => 1, 'boolean?' => 1, 'bound-identifier=?' => 1, 'buffer-mode' => 1, 'buffer-mode?' => 1, 'bytevector->sint-list' => 1, 'bytevector->string' => 1, 'bytevector->u8-list' => 1, 'bytevector->uint-list' => 1, 'bytevector-copy' => 1, 'bytevector-copy!' => 1, 'bytevector-fill!' => 1, 'bytevector-ieee-double-native-ref' => 1, 'bytevector-ieee-double-native-set!' => 1, 'bytevector-ieee-double-ref' => 1, 'bytevector-ieee-double-set!' => 1, 'bytevector-ieee-single-native-ref' => 1, 'bytevector-ieee-single-native-set!' => 1, 'bytevector-ieee-single-ref' => 1, 'bytevector-ieee-single-set!' => 1, 'bytevector-length' => 1, 'bytevector-s16-native-ref' => 1, 'bytevector-s16-native-set!' => 1, 'bytevector-s16-ref' => 1, 'bytevector-s16-set!' => 1, 'bytevector-s32-native-ref' => 1, 'bytevector-s32-native-set!' => 1, 'bytevector-s32-ref' => 1, 'bytevector-s32-set!' => 1, 'bytevector-s64-native-ref' => 1, 'bytevector-s64-native-set!' => 1, 'bytevector-s64-ref' => 1, 'bytevector-s64-set!' => 1, 'bytevector-s8-ref' => 1, 'bytevector-s8-set!' => 1, 'bytevector-sint-ref' => 1, 'bytevector-sint-set!' => 1, 'bytevector-u16-native-ref' => 1, 'bytevector-u16-native-set!' => 1, 'bytevector-u16-ref' => 1, 'bytevector-u16-set!' => 1, 'bytevector-u32-native-ref' => 1, 'bytevector-u32-native-set!' => 1, 'bytevector-u32-ref' => 1, 'bytevector-u32-set!' => 1, 'bytevector-u64-native-ref' => 1, 'bytevector-u64-native-set!' => 1, 'bytevector-u64-ref' => 1, 'bytevector-u64-set!' => 1, 'bytevector-u8-ref' => 1, 'bytevector-u8-set!' => 1, 'bytevector-uint-ref' => 1, 'bytevector-uint-set!' => 1, 'bytevector=?' => 1, 'bytevector?' => 1, 'caaaar' => 1, 'caaadr' => 1, 'caaar' => 1, 'caadar' => 1, 'caaddr' => 1, 'caadr' => 1, 'caar' => 1, 'cadaar' => 1, 'cadadr' => 1, 'cadar' => 1, 'caddar' => 1, 'cadddr' => 1, 'caddr' => 1, 'cadr' => 1, 'call-with-bytevector-output-port' => 1, 'call-with-bytevector-output-port' => 1, 'call-with-current-continuation' => 1, 'call-with-input-file' => 1, 'call-with-output-file' => 1, 'call-with-port' => 1, 'call-with-string-output-port' => 1, 'call-with-values' => 1, 'call/cc' => 1, 'car' => 1, 'case' => 1, 'case-lambda' => 1, 'cdaaar' => 1, 'cdaadr' => 1, 'cdaar' => 1, 'cdadar' => 1, 'cdaddr' => 1, 'cdadr' => 1, 'cdar' => 1, 'cddaar' => 1, 'cddadr' => 1, 'cddar' => 1, 'cdddar' => 1, 'cddddr' => 1, 'cdddr' => 1, 'cddr' => 1, 'cdr' => 1, 'ceiling' => 1, 'char->integer' => 1, 'char-alphabetic?' => 1, 'char-ci<=?' => 1, 'char-ci<?' => 1, 'char-ci=?' => 1, 'char-ci>=?' => 1, 'char-ci>?' => 1, 'char-downcase' => 1, 'char-foldcase' => 1, 'char-general-category' => 1, 'char-lower-case?' => 1, 'char-numeric?' => 1, 'char-title-case?' => 1, 'char-titlecase' => 1, 'char-upcase' => 1, 'char-upper-case?' => 1, 'char-whitespace?' => 1, 'char<=?' => 1, 'char<?' => 1, 'char=?' => 1, 'char>=?' => 1, 'char>?' => 1, 'char?' => 1, 'close-input-port' => 1, 'close-output-port' => 1, 'close-port' => 1, 'command-line' => 1, 'complex?' => 1, 'cond' => 1, 'condition' => 1, 'condition-accessor' => 1, 'condition-irritants' => 1, 'condition-message' => 1, 'condition-predicate' => 1, 'condition-who' => 1, 'condition?' => 1, 'cons' => 1, 'cons*' => 1, 'constant' => 1, 'cos' => 1, 'current-error-port' => 1, 'current-input-port' => 1, 'current-output-port' => 1, 'datum->syntax' => 1, 'define' => 1, 'define' => 1, 'define' => 1, 'define' => 1, 'define' => 1, 'define-condition-type' => 1, 'define-enumeration' => 1, 'define-record-type' => 1, 'define-record-type' => 1, 'define-syntax' => 1, 'delay' => 1, 'delete-file' => 1, 'denominator' => 1, 'display' => 1, 'display' => 1, 'div' => 1, 'div-and-mod' => 1, 'divdiv1-and-moddo' => 1, 'dynamic-wind' => 1, 'else' => 1, 'endianness' => 1, 'enum-set->list' => 1, 'enum-set-complement' => 1, 'enum-set-constructor' => 1, 'enum-set-difference' => 1, 'enum-set-indexer' => 1, 'enum-set-intersection' => 1, 'enum-set-member?' => 1, 'enum-set-projection' => 1, 'enum-set-subset?' => 1, 'enum-set-union' => 1, 'enum-set-universe' => 1, 'enum-set=?' => 1, 'environment' => 1, 'eof-object' => 1, 'eof-object?' => 1, 'eol-style' => 1, 'eq?' => 1, 'equal-hash' => 1, 'equal?' => 1, 'eqv?' => 1, 'error' => 1, 'error-handling-mode' => 1, 'error?' => 1, 'eval' => 1, 'even?' => 1, 'exact' => 1, 'exact->inexact' => 1, 'exact-integer-sqrt' => 1, 'exact?' => 1, 'exists' => 1, 'exit' => 1, 'exit' => 1, 'exp' => 1, 'expt' => 1, 'fields' => 1, 'file-exists?' => 1, 'file-options' => 1, 'filter' => 1, 'find' => 1, 'finite?' => 1, 'fixnum->flonum' => 1, 'fixnum-width' => 1, 'fixnum?' => 1, 'fl*' => 1, 'fl+' => 1, 'fl-' => 1, 'fl-' => 1, 'fl/' => 1, 'fl/' => 1, 'fl<=?' => 1, 'fl<?' => 1, 'fl=?' => 1, 'fl>=?' => 1, 'fl>?' => 1, 'flabs' => 1, 'flacos' => 1, 'flasin' => 1, 'flatan' => 1, 'flatan' => 1, 'flceiling' => 1, 'flcos' => 1, 'fldenominator' => 1, 'fldiv' => 1, 'fldiv-and-mod' => 1, 'fldivfldiv1-and-modfleven?' => 1, 'flexp' => 1, 'flexpt' => 1, 'flfinite?' => 1, 'flfloor' => 1, 'flinfinite?' => 1, 'flinteger?' => 1, 'fllog' => 1, 'fllog' => 1, 'flmax' => 1, 'flmin' => 1, 'flmod' => 1, 'flmodflnan?' => 1, 'flnegative?' => 1, 'flnumerator' => 1, 'flodd?' => 1, 'flonum?' => 1, 'floor' => 1, 'flpositive?' => 1, 'flround' => 1, 'flsin' => 1, 'flsqrt' => 1, 'fltan' => 1, 'fltruncate' => 1, 'flush-output-port' => 1, 'flzero?' => 1, 'fold-left' => 1, 'fold-right' => 1, 'for-all' => 1, 'for-each' => 1, 'force' => 1, 'free-identifier=?' => 1, 'fx*' => 1, 'fx*/carry' => 1, 'fx+' => 1, 'fx+/carry' => 1, 'fx-' => 1, 'fx-' => 1, 'fx-/carry' => 1, 'fx<=?' => 1, 'fx<?' => 1, 'fx=?' => 1, 'fx>=?' => 1, 'fx>?' => 1, 'fxand' => 1, 'fxarithmetic-shift' => 1, 'fxarithmetic-shift-left' => 1, 'fxarithmetic-shift-right' => 1, 'fxbit-count' => 1, 'fxbit-field' => 1, 'fxbit-set?' => 1, 'fxcopy-bit' => 1, 'fxcopy-bit-field' => 1, 'fxdiv' => 1, 'fxdiv-and-mod' => 1, 'fxdivfxdiv1-and-modfxeven?' => 1, 'fxfirst-bit-set' => 1, 'fxif' => 1, 'fxior' => 1, 'fxlength' => 1, 'fxmax' => 1, 'fxmin' => 1, 'fxmod' => 1, 'fxmodfxnegative?' => 1, 'fxnot' => 1, 'fxodd?' => 1, 'fxpositive?' => 1, 'fxreverse-bit-field' => 1, 'fxrotate-bit-field' => 1, 'fxxor' => 1, 'fxzero?' => 1, 'gcd' => 1, 'generate-temporaries' => 1, 'get-bytevector-all' => 1, 'get-bytevector-n' => 1, 'get-bytevector-n!' => 1, 'get-bytevector-some' => 1, 'get-char' => 1, 'get-datum' => 1, 'get-line' => 1, 'get-string-all' => 1, 'get-string-n' => 1, 'get-string-n!' => 1, 'get-u8' => 1, 'greatest-fixnum' => 1, 'guard' => 1, 'hashtable-clear!' => 1, 'hashtable-clear!' => 1, 'hashtable-contains?' => 1, 'hashtable-copy' => 1, 'hashtable-copy' => 1, 'hashtable-delete!' => 1, 'hashtable-entries' => 1, 'hashtable-equivalence-function' => 1, 'hashtable-hash-function' => 1, 'hashtable-keys' => 1, 'hashtable-mutable?' => 1, 'hashtable-ref' => 1, 'hashtable-set!' => 1, 'hashtable-size' => 1, 'hashtable-update!' => 1, 'hashtable?' => 1, 'i/o-decoding-error?' => 1, 'i/o-encoding-error-char' => 1, 'i/o-encoding-error?' => 1, 'i/o-error-filename' => 1, 'i/o-error-port' => 1, 'i/o-error-position' => 1, 'i/o-error?' => 1, 'i/o-file-already-exists-error?' => 1, 'i/o-file-does-not-exist-error?' => 1, 'i/o-file-is-read-only-error?' => 1, 'i/o-file-protection-error?' => 1, 'i/o-filename-error?' => 1, 'i/o-invalid-position-error?' => 1, 'i/o-port-error?' => 1, 'i/o-read-error?' => 1, 'i/o-write-error?' => 1, 'identifier-syntax' => 1, 'identifier-syntax' => 1, 'identifier?' => 1, 'if' => 1, 'if' => 1, 'imag-part' => 1, 'immutable' => 1, 'implementation-restriction-violation?' => 1, 'inexact' => 1, 'inexact->exact' => 1, 'inexact?' => 1, 'infinite?' => 1, 'input-port?' => 1, 'integer->char' => 1, 'integer-valued?' => 1, 'integer?' => 1, 'irritants-condition?' => 1, 'lambda' => 1, 'latin-1-codec' => 1, 'lcm' => 1, 'least-fixnum' => 1, 'length' => 1, 'let' => 1, 'let' => 1, 'let*' => 1, 'let*-values' => 1, 'let-syntax' => 1, 'let-values' => 1, 'letrec' => 1, 'letrec*' => 1, 'letrec-syntax' => 1, 'lexical-violation?' => 1, 'list' => 1, 'list->string' => 1, 'list->vector' => 1, 'list-ref' => 1, 'list-sort' => 1, 'list-tail' => 1, 'list?' => 1, 'log' => 1, 'log' => 1, 'lookahead-char' => 1, 'lookahead-u8' => 1, 'magnitude' => 1, 'make-assertion-violation' => 1, 'make-bytevector' => 1, 'make-bytevector' => 1, 'make-custom-binary-input-port' => 1, 'make-custom-binary-input/output-port' => 1, 'make-custom-binary-output-port' => 1, 'make-custom-textual-input-port' => 1, 'make-custom-textual-input/output-port' => 1, 'make-custom-textual-output-port' => 1, 'make-enumeration' => 1, 'make-eq-hashtable' => 1, 'make-eq-hashtable' => 1, 'make-eqv-hashtable' => 1, 'make-eqv-hashtable' => 1, 'make-error' => 1, 'make-hashtable' => 1, 'make-hashtable' => 1, 'make-i/o-decoding-error' => 1, 'make-i/o-encoding-error' => 1, 'make-i/o-error' => 1, 'make-i/o-file-already-exists-error' => 1, 'make-i/o-file-does-not-exist-error' => 1, 'make-i/o-file-is-read-only-error' => 1, 'make-i/o-file-protection-error' => 1, 'make-i/o-filename-error' => 1, 'make-i/o-invalid-position-error' => 1, 'make-i/o-port-error' => 1, 'make-i/o-read-error' => 1, 'make-i/o-write-error' => 1, 'make-implementation-restriction-violation' => 1, 'make-irritants-condition' => 1, 'make-lexical-violation' => 1, 'make-message-condition' => 1, 'make-no-infinities-violation' => 1, 'make-no-nans-violation' => 1, 'make-non-continuable-violation' => 1, 'make-polar' => 1, 'make-record-constructor-descriptor' => 1, 'make-record-type-descriptor' => 1, 'make-rectangular' => 1, 'make-serious-condition' => 1, 'make-string' => 1, 'make-string' => 1, 'make-syntax-violation' => 1, 'make-transcoder' => 1, 'make-transcoder' => 1, 'make-transcoder' => 1, 'make-undefined-violation' => 1, 'make-variable-transformer' => 1, 'make-vector' => 1, 'make-vector' => 1, 'make-violation' => 1, 'make-warning' => 1, 'make-who-condition' => 1, 'map' => 1, 'max' => 1, 'member' => 1, 'memp' => 1, 'memq' => 1, 'memv' => 1, 'message-condition?' => 1, 'min' => 1, 'mod' => 1, 'modmodulo' => 1, 'mutable' => 1, 'nan?' => 1, 'native-endianness' => 1, 'native-eol-style' => 1, 'native-transcoder' => 1, 'negative?' => 1, 'newline' => 1, 'newline' => 1, 'no-infinities-violation?' => 1, 'no-nans-violation?' => 1, 'non-continuable-violation?' => 1, 'nongenerative' => 1, 'not' => 1, 'null-environment' => 1, 'null?' => 1, 'number->string' => 1, 'number->string' => 1, 'number->string' => 1, 'number?' => 1, 'numerator' => 1, 'odd?' => 1, 'opaque' => 1, 'open-bytevector-input-port' => 1, 'open-bytevector-input-port' => 1, 'open-bytevector-output-port' => 1, 'open-bytevector-output-port' => 1, 'open-file-input-port' => 1, 'open-file-input-port' => 1, 'open-file-input-port' => 1, 'open-file-input-port' => 1, 'open-file-input/output-port' => 1, 'open-file-input/output-port' => 1, 'open-file-input/output-port' => 1, 'open-file-input/output-port' => 1, 'open-file-output-port' => 1, 'open-file-output-port' => 1, 'open-file-output-port' => 1, 'open-file-output-port' => 1, 'open-input-file' => 1, 'open-output-file' => 1, 'open-string-input-port' => 1, 'open-string-output-port' => 1, 'or' => 1, 'output-port-buffer-mode' => 1, 'output-port?' => 1, 'pair?' => 1, 'parent' => 1, 'parent-rtd' => 1, 'partition' => 1, 'peek-char' => 1, 'peek-char' => 1, 'port-eof?' => 1, 'port-has-port-position?' => 1, 'port-has-set-port-position!?' => 1, 'port-position' => 1, 'port-transcoder' => 1, 'port?' => 1, 'positive?' => 1, 'exprprocedure?' => 1, 'protocol' => 1, 'put-bytevector' => 1, 'put-bytevector' => 1, 'put-bytevector' => 1, 'put-char' => 1, 'put-datum' => 1, 'put-string' => 1, 'put-string' => 1, 'put-string' => 1, 'put-u8' => 1, 'quasiquote' => 1, 'quasisyntax' => 1, 'quote' => 1, 'quotient' => 1, 'raise' => 1, 'raise-continuable' => 1, 'rational-valued?' => 1, 'rational?' => 1, 'rationalize' => 1, 'read' => 1, 'read' => 1, 'read-char' => 1, 'read-char' => 1, 'real->flonum' => 1, 'real-part' => 1, 'real-valued?' => 1, 'real?' => 1, 'record-accessor' => 1, 'record-constructor' => 1, 'record-constructor-descriptor' => 1, 'record-field-mutable?' => 1, 'record-mutator' => 1, 'record-predicate' => 1, 'record-rtd' => 1, 'record-type-descriptor' => 1, 'record-type-descriptor?' => 1, 'record-type-field-names' => 1, 'record-type-generative?' => 1, 'record-type-name' => 1, 'record-type-opaque?' => 1, 'record-type-parent' => 1, 'record-type-sealed?' => 1, 'record-type-uid' => 1, 'record?' => 1, 'remainder' => 1, 'remove' => 1, 'remp' => 1, 'remq' => 1, 'remv' => 1, 'reverse' => 1, 'round' => 1, 'scheme-report-environment' => 1, 'sealed' => 1, 'serious-condition?' => 1, 'set!' => 1, 'set-car!' => 1, 'set-cdr!' => 1, 'set-port-position!' => 1, 'simple-conditions' => 1, 'sin' => 1, 'sint-list->bytevector' => 1, 'sqrt' => 1, 'standard-error-port' => 1, 'standard-input-port' => 1, 'standard-output-port' => 1, 'string' => 1, 'string->bytevector' => 1, 'string->list' => 1, 'string->number' => 1, 'string->number' => 1, 'string->symbol' => 1, 'string->utf16' => 1, 'string->utf16' => 1, 'string->utf32' => 1, 'string->utf32' => 1, 'string->utf8' => 1, 'string-append' => 1, 'string-ci-hash' => 1, 'string-ci<=?' => 1, 'string-ci<?' => 1, 'string-ci=?' => 1, 'string-ci>=?' => 1, 'string-ci>?' => 1, 'string-copy' => 1, 'string-downcase' => 1, 'string-fill!' => 1, 'string-foldcase' => 1, 'string-for-each' => 1, 'string-hash' => 1, 'string-length' => 1, 'string-normalize-nfc' => 1, 'string-normalize-nfd' => 1, 'string-normalize-nfkc' => 1, 'string-normalize-nfkd' => 1, 'string-ref' => 1, 'string-set!' => 1, 'string-titlecase' => 1, 'string-upcase' => 1, 'string<=?' => 1, 'string<?' => 1, 'string=?' => 1, 'string>=?' => 1, 'string>?' => 1, 'string?' => 1, 'substring' => 1, 'symbol->string' => 1, 'symbol-hash' => 1, 'symbol=?' => 1, 'symbol?' => 1, 'syntax' => 1, 'syntax->datum' => 1, 'syntax-case' => 1, 'syntax-rules' => 1, 'syntax-violation' => 1, 'syntax-violation' => 1, 'syntax-violation-form' => 1, 'syntax-violation-subform' => 1, 'syntax-violation?' => 1, 'tan' => 1, 'textual-port?' => 1, 'transcoded-port' => 1, 'transcoder-codec' => 1, 'transcoder-eol-style' => 1, 'transcoder-error-handling-mode' => 1, 'truncate' => 1, 'u8-list->bytevector' => 1, 'uint-list->bytevector' => 1, 'undefined-violation?' => 1, 'unless' => 1, 'unquote' => 1, 'unquote-splicing' => 1, 'unsyntax' => 1, 'unsyntax-splicing' => 1, 'utf-16-codec' => 1, 'utf-8-codec' => 1, 'utf16->string' => 1, 'utf16->string' => 1, 'utf32->string' => 1, 'utf32->string' => 1, 'utf8->string' => 1, 'values' => 1, 'variable' => 1, 'vector' => 1, 'vector->list' => 1, 'vector-fill!' => 1, 'vector-for-each' => 1, 'vector-length' => 1, 'vector-map' => 1, 'vector-ref' => 1, 'vector-set!' => 1, 'vector-sort' => 1, 'vector-sort!' => 1, 'vector?' => 1, 'violation?' => 1, 'warning?' => 1, 'when' => 1, 'who-condition?' => 1, 'with-exception-handler' => 1, 'with-input-from-file' => 1, 'with-output-to-file' => 1, 'with-syntax' => 1, 'write' => 1, 'write' => 1, 'write-char' => 1, 'write-char' => 1, 'zero?' => 1, 
);
 map { $interns{$_} = 1 } 
    (',' ,
    '#,', 
    '#,@', 
    "#'",  
    "`", 
    '=>' ,  
    '_',  
    '...',
    "#`" );

    return \%interns;
}

main();

