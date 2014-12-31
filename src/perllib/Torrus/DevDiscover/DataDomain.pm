#  Copyright (C) 2014 Roman Hochuli
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.

# Roman Hochuli <roman@hochu.li>

# Interesting EMC DataDomain MIBs

package Torrus::DevDiscover::DataDomain;

use strict;
use warnings;

use Torrus::Log;


$Torrus::DevDiscover::registry{'DataDomain'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
};


our %oiddef = (
     # DATA-DOMAIN-MIB
     'dd'                                => '1.3.6.1.4.1.19746',
     
     # DATA-DOMAIN-MIB system properties
     'ddSystemPropertiesTable'           => '1.3.6.1.4.1.19746.1.13.1',
     'ddSystemPropertiesSerialNumber'    => '1.3.6.1.4.1.19746.1.13.1.1.0',
     'ddSystemPropertiesSystemVersion'   => '1.3.6.1.4.1.19746.1.13.1.3.0',
     'ddSystemPropertiesModelNumber'     => '1.3.6.1.4.1.19746.1.13.1.4.0',

     # DATA-DOMAIN-MIB FileSystems
     'ddFilesystem'                      => '1.3.6.1.4.1.19746.1.3',

     # DATA-DOMAIN-MIB FileSystemsProperties
     'ddFilesystemPropertiesTable'       => '1.3.6.1.4.1.19746.1.3.1',
     'ddFilesystemPropertiesStatus'      => '1.3.6.1.4.1.19746.1.3.1.1',

     # DATA-DOMAIN-MIB FileSystemSpace
     'ddFilesystemSpaceTable'            => '1.3.6.1.4.1.19746.1.3.2',
     'ddFilesystemSpaceResourceIndex'    => '1.3.6.1.4.1.19746.1.3.2.1.1.1',
     'ddFilesystemSpaceResourceName'     => '1.3.6.1.4.1.19746.1.3.2.1.1.3',

     # DATA-DOMAIN-MIB mtree
     'ddMtreeList'                       => '1.3.6.1.4.1.19746.1.15',
     'ddMtreeListTable'                  => '1.3.6.1.4.1.19746.1.15.2.1',
     'ddMtreeListEntry'                  => '1.3.6.1.4.1.19746.1.15.2.1.1',
     'ddMtreeListName'                   => '1.3.6.1.4.1.19746.1.15.2.1.1.2',
     'ddMtreeListPreCompGib'             => '1.3.6.1.4.1.19746.1.15.2.1.1.3',
);



sub checkdevtype {
    my $dd = shift;
    my $devdetails = shift;
    my $retval = 0;

    if( $dd->oidBaseMatch ( 'dd', $devdetails->snmpVar( $dd->oiddef('sysObjectID') ) ) ) {
            $retval = 1;
    }
    
    return $retval;
}


sub discover {
    my $dd = shift;
    my $devdetails = shift;

    my $session = $dd->session();
    my $data = $devdetails->data();

    # NOTE: Comments and Serial number of device
    
    my $chassis = $dd->retrieveSnmpOIDs( 'ddSystemPropertiesSerialNumber',
                                         'ddSystemPropertiesSystemVersion',
                                         'ddSystemPropertiesModelNumber' );
    
    Debug('ddSystemPropertiesModenNumber=' . $chassis->{'ddSystemPropertiesModelNumber'});
    Debug('ddSystemPropertiesSystemVersion=' . $chassis->{'ddSystemPropertiesSystemVersion'});
    Debug('ddSystemPropertiesSerialNumber=' . $chassis->{'ddSystemPropertiesSerialNumber'});
    
    my $deviceComment = 
        'DataDomain ' . $chassis->{'ddSystemPropertiesModelNumber'} . 
        ', Serialnumber ' . $chassis->{'ddSystemPropertiesSerialNumber'} . 
        ', running ' . $chassis->{'ddSystemPropertiesSystemVersion'};
    
    $data->{'param'}{'comment'} = $deviceComment;

    # discover Filesystem-related stuff
    if( $dd->checkSnmpTable('ddFilesystemPropertiesTable') ) {
        $devdetails->setCap('ddFilesystem');
        $data->{'ddFilesystem'} = {};

        # get FilesystemProperties-Status
        {
            my $table = $dd->walkSnmpTable('ddFilesystemPropertiesStatus');
            while( my( $fsIndex, $status ) = each %{$table} ) {
                $data->{'ddFilesystem'}{'properties'}{$fsIndex}{'status'} = $status;
#                Debug("Found Filesystem " . $fsIndex . " in status " . $status);
            }
        }

        # get FilesystemSpaces-Status
        {
            my $table = $dd->walkSnmpTable('ddFilesystemSpaceResourceName');
            while( my( $fssIndex, $spaceName ) = each %{$table} ) {
                # make sure we remove slashes and replace them with underscore...
                $data->{'ddFilesystem'}{'space'}{$fssIndex}{'name'} = $spaceName;
                $data->{'ddFilesystem'}{'space'}{$fssIndex}{'name'} =~ s/^\///;
                $data->{'ddFilesystem'}{'space'}{$fssIndex}{'name'} =~ s/\//_/;
#                Debug("Found FilesystemSpace " . $fssIndex . " named " . $data->{'ddFilesystem'}{'space'}{$fssIndex}{'name'});
            }
        }
    }

    # discover Mtrees
    if( $dd->checkSnmpTable('ddMtreeListTable') ) {
        $devdetails->setCap('ddMtree'); 
        $data->{'ddMtree'} = {};

        # get Mtree Names
        {
            my $table = $dd->walkSnmpTable('ddMtreeListName');
            while( my( $mtreeIndex, $name ) = each %{$table} ) {
                    $data->{'ddMtree'}{$mtreeIndex}{'name'} = $name;
            }
        }
    }

    return 1;
}


sub buildConfig {
    my $devdetails = shift;
    my $cb = shift;
    my $devNode = shift;
    my $vspath = "/";

    my $data = $devdetails->data();
    Debug("Looks like we have got ourself a DataDomain system here.");

    # Filesystem Stats
    if( $devdetails->hasCap('ddFilesystem') ) {
        my $ddNode = $devNode;
        Debug("This DataDomain has ddFilesystem capability.");

        #
        # Work FilesytemProperties
        if( scalar(keys %{$data->{'ddFilesystem'}{'properties'}}) >= 1 ) {
            Debug("And apparently it has Filesystems configured.");
            my $param = {
                'node-display-name' => 'Filesystem',
                'comment' => 'Filesystem statistics',
            };

#            Debug("OK, then let's give us an Filesystem-Subtree onto that device...");
            my $fsSubtree = $cb->addSubtree( $ddNode, 'Filesystem', $param );
#            Debug("...apply the Overview template...");
            $cb->addTemplateApplication( $fsSubtree,
                                         'DataDomain::dd-filesystem-overview' );

            foreach my $fsIndex ( sort {$a <=> $b} keys %{$data->{'ddFilesystem'}{'properties'}} ) {
                if( $data->{'ddFilesystem'}{'properties'}{$fsIndex}{'status'} eq '3') {
#                    Debug("Found filesystem " . $fsIndex . " in running state.");

                    my $fsParam = {
                        'comment'  => "Filesystem " . $fsIndex,
                        'dd-fs-index' => $fsIndex,
                        'dd-fs-name' => $fsIndex,
                        'nodeid' => 'ddfs/%nodeid-device%/' . $fsIndex,
                    };

#                    Debug("Adding a Subtree for that Filesystem then.");
                    my $fsNode =
                        $cb->addSubtree( $fsSubtree, 'Filesystem_' . $fsIndex, $fsParam,
                                         ['DataDomain::dd-filesystem-subtree']);
                    $vspath = $cb->getElementPath($fsNode);
                }
            }
        }

        #
        # Work FilesytemSpace
        if( scalar(keys %{$data->{'ddFilesystem'}{'space'}}) >= 1 ) {
            Debug("And apparently it has FilesystemSpaces configured.");
            my $param = {
                'node-display-name' => 'FilesystemSpaces',
                'comment' => 'FilesystemSpace statistics',
            };

#            Debug("OK, then let's give us an FilesystemSpaces-Subtree onto that device...");
            my $fssSubtree = $cb->addSubtree( $ddNode, 'FilesystemSpaces', $param );
#            Debug("...apply the Overview template...");
            $cb->addTemplateApplication( $fssSubtree,
                                         'DataDomain::dd-filesystemspace-overview' );

            foreach my $fssIndex ( sort {$a <=> $b} keys %{$data->{'ddFilesystem'}{'space'}} ) {
#                Debug("Found FilesystemSpace " . $fssIndex . " named " . $data->{'ddFilesystem'}{'space'}{$fssIndex}{'name'});

                my $fssParam = {
                    'comment'  => "FilesystemSpace " . $data->{'ddFilesystem'}{'space'}{$fssIndex}{'name'},
                    'dd-fss-index' => $fssIndex,
                    'dd-fss-name' => $data->{'ddFilesystem'}{'space'}{$fssIndex}{'name'},
                    'dd-fss-filename' => $data->{'ddFilesystem'}{'space'}{$fssIndex}{'name'},
                    'nodeid' => 'ddfss/%nodeid-device%/' . $fssIndex,
                };

#                Debug("Adding a Subtree for that Filesystem then.");
                my $fsNode =
                    $cb->addSubtree( $fssSubtree, 'Filesystem_' . $data->{'ddFilesystem'}{'space'}{$fssIndex}{'name'}, $fssParam,
                                     ['DataDomain::dd-filesystemspace-subtree']);

                if( $data->{'ddFilesystem'}{'space'}{$fssIndex}{'name'} eq "Data" ) {
                   if( $vspath ne "/" ) {
                      $fssParam->{'nodeid'} = 'ddfss/%nodeid-device%/totcompfact';
                      $fssParam->{'totcompfac-vspath'} = $vspath;
                      my $fsCompFactor = $cb->addLeaf($fsNode, 'Total_Compression_Factor', $fssParam,
                                              ['DataDomain::dd-filesystemspace-compfactor']);
                   }
                }
            }
        }

    }

    #
    # Mtree Stats
    if( $devdetails->hasCap('ddMtree') ) {
        my $ddNode = $devNode;
        Debug("This DataDomain has ddMtree capability.");
        

        if( scalar(keys %{$data->{'ddMtree'}}) >= 1 ) {
#            Debug("And apparently it has Mtrees configured.");
            my $param = {
                'node-display-name' => 'Mtree',
                'comment' => 'Mtree statistics',
            };

#            Debug("OK, then let's give us an Mtree-Subtree onto that device...");
            my $mtreeSubtree = $cb->addSubtree( $ddNode, 'Mtree', $param );
#            Debug("...apply the Overview template...");
            $cb->addTemplateApplication( $mtreeSubtree,
                                         'DataDomain::dd-mtree-overview' );

#            Debug("...and loop thru all the configured Mtrees.");
            foreach my $mtreeIndex ( sort {$a <=> $b} keys %{$data->{'ddMtree'}} ) {
#                Debug("This Mtree is called: " . $data->{'ddMtree'}{$mtreeIndex}{'name'});

                # 
                # As of the bitter realisation the index of Mtrees is not fix and may
                # change at any time an Mtree is added or removed. This we must take 
                # care of to have a stable filename. We base it on the Mtrees name in
                # this case and hope nobody comes ever to the idea of changing an
                # Mtrees name which is actually possible on the UI... *sigh*
                $data->{'ddMtree'}{$mtreeIndex}{'sanitizedname'} = $data->{'ddMtree'}{$mtreeIndex}{'name'};
                $data->{'ddMtree'}{$mtreeIndex}{'sanitizedname'} =~ s/^\///;
                $data->{'ddMtree'}{$mtreeIndex}{'sanitizedname'} =~ s/\//_/g;

                my $mtreeName = $data->{'ddMtree'}{$mtreeIndex}{'name'};
                my $mtreeParam = {
                    'comment'  => "Mtree " . $mtreeName,
                    'dd-mtree-index' => $mtreeIndex,
                    'dd-mtree-name' => $mtreeName,
                    'dd-mtree-filename' => $data->{'ddMtree'}{$mtreeIndex}{'sanitizedname'},
                    'nodeid' => 'ddmt/%nodeid-device%/' . $mtreeIndex,
                };
                
#                Debug("Adding a Subtree for that Mtree then.");
                my $mtreeNode =
                    $cb->addSubtree( $mtreeSubtree, 'Mtree_' . $mtreeIndex, $mtreeParam,
                                     ['DataDomain::dd-mtree-subtree']);
            } 
        }
    }

    return;
}

1;
