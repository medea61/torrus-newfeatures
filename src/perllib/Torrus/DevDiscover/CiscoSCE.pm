#
#  Discovery module for Cisco Service Control Engine (formely PCube)
#
#  Copyright (C) 2006 Jon Nistor
#  Copyright (C) 2006 Stanislav Sinyagin
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

# $Id$
# Jon Nistor <nistor at snickers dot org>
#


# Cisco SCE devices discovery
package Torrus::DevDiscover::CiscoSCE;

use strict;
use Torrus::Log;


$Torrus::DevDiscover::registry{'CiscoSCE'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };

# pmodule-dependend OIDs are presented for module #1 only.
# currently devices with more than one module do not exist

our %oiddef =
    (
     # PCUBE-SE-MIB
     'pcubeProducts'        => '1.3.6.1.4.1.5655.1',
     'pchassisSysType'      => '1.3.6.1.4.1.5655.4.1.2.1.0',
     'pchassisNumSlots'     => '1.3.6.1.4.1.5655.4.1.2.6.0',
     'pmoduleType'          => '1.3.6.1.4.1.5655.4.1.3.1.1.2.1',
     'pmoduleNumLinks'      => '1.3.6.1.4.1.5655.4.1.3.1.1.7.1',
     'pmoduleSerialNumber'  => '1.3.6.1.4.1.5655.4.1.3.1.1.9.1',
     'pmoduleNumTrafficProcessors' => '1.3.6.1.4.1.5655.4.1.3.1.1.3.1',
     'subscribersNumIpAddrMappings'  => '1.3.6.1.4.1.5655.4.1.8.1.1.3.1',
     'subscribersNumIpRangeMappings' => '1.3.6.1.4.1.5655.4.1.8.1.1.5.1',
     'subscribersNumVlanMappings'    => '1.3.6.1.4.1.5655.4.1.8.1.1.7.1',
     'subscribersNumAnonymous'       => '1.3.6.1.4.1.5655.4.1.8.1.1.16.1',
     'pportNumTxQueues'     => '1.3.6.1.4.1.5655.4.1.10.1.1.4.1',
     'pportIfIndex'         => '1.3.6.1.4.1.5655.4.1.10.1.1.5.1',
     'txQueuesDescription'  => '1.3.6.1.4.1.5655.4.1.11.1.1.4.1',

     # CISCO-SCAS-BB-MIB (PCUBE-ENGAGE-MIB)
     'globalScopeServiceCounterName' => '1.3.6.1.4.1.5655.4.2.5.1.1.3.1',
     
     );

our %sceChassisNames =
    (
     '1'    => 'unknown',
     '2'    => 'SE 1000',
     '3'    => 'SE 100',
     '4'    => 'SE 2000',
    );

our %sceModuleDesc =
    (
     '1'    => 'unknown',
     '2'    => '2xGBE + 1xFE Mgmt',
     '3'    => '2xFE + 1xFE Mgmt',
     '4'    => '4xGBE + 1 or 2 FastE Mgmt',
     '5'    => '4xFE + 1xFE Mgmt',
     '6'    => '4xOC-12 + 1 or 2 FastE Mgmt',
     '7'    => '16xFE + 2xGBE, 2 FastE Mgmt',
    );

sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    if( not $dd->oidBaseMatch
        ( 'pcubeProducts',
          $devdetails->snmpVar( $dd->oiddef('sysObjectID') ) ) )
    {
        return 0;
    }
    
    my $result = $dd->retrieveSnmpOIDs('pchassisNumSlots');
    if( $result->{'pchassisNumSlots'} > 1 )
    {
        Error('This SCE device has more than one module on the chassis.' .
              'The current version of DevDiscover does not support such ' .
              'devices');
        return 0;
    }
            
    $devdetails->setCap('interfaceIndexingPersistent');

    return 1;
}

sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $session = $dd->session();
    my $data = $devdetails->data();

    # Get the system info and display it in the comment
    my $sceInfo = $dd->retrieveSnmpOIDs
        ( 'pchassisSysType', 'pmoduleType', 'pmoduleNumLinks',
          'pmoduleSerialNumber', 'pmoduleNumTrafficProcessors',
          'subscribersNumIpAddrMappings', 'subscribersNumIpRangeMappings',
          'subscribersNumVlanMappings', 'subscribersNumAnonymous' );

    $data->{'sceInfo'} = $sceInfo;
    
    $data->{'param'}{'comment'} =
        $sceChassisNames{$sceInfo->{'pchassisSysType'}} .
        " chassis, " . $sceModuleDesc{$sceInfo->{'pmoduleType'}} .
        ", Hw Serial#: " . $sceInfo->{'pmoduleSerialNumber'};
    
    $data->{'sceTrafficProcessors'} =
        $sceInfo->{'pmoduleNumTrafficProcessors'};

    # Check if the installation is subscriber-aware
    
    if( $sceInfo->{'subscribersNumIpAddrMappings'} > 0 or
        $sceInfo->{'subscribersNumIpRangeMappings'} > 0 or
        $sceInfo->{'subscribersNumVlanMappings'} > 0 or
        $sceInfo->{'subscribersNumAnonymous'} > 0 )
    {
        $devdetails->setCap('sceSubscribers');
    }
    
    # Get the names of TX queues
    
    my $txQueueNum = $session->get_table
        ( -baseoid => $dd->oiddef('pportNumTxQueues') );
    
     $devdetails->storeSnmpVars( $txQueueNum );
    
    my $ifIndexTable = $session->get_table
        ( -baseoid => $dd->oiddef('pportIfIndex') );

    my $txQueueDesc = $session->get_table
        ( -baseoid => $dd->oiddef('txQueuesDescription') );
    
    $devdetails->storeSnmpVars( $txQueueDesc );
    
    foreach my $pIndex
        ( $devdetails->getSnmpIndices( $dd->oiddef('pportNumTxQueues') ) )
    {
        # We take ports with more than one queue and add queueing
        # statistics to interface counters
        if( $txQueueNum->{$dd->oiddef('pportNumTxQueues') .
                              '.' . $pIndex} > 1 )
        {
            # We need the ifIndex to retrieve the interface name
            
            my $ifIndex =
                $ifIndexTable->{$dd->oiddef('pportIfIndex') . '.' . $pIndex};

            $data->{'scePortIfIndex'}{$pIndex} = $ifIndex;
            
            foreach my $qIndex
                ( $devdetails->getSnmpIndices
                  ( $dd->oiddef('txQueuesDescription') . '.' . $pIndex ) )
            {
                my $oid = $dd->oiddef('txQueuesDescription') . '.' .
                    $pIndex . '.' . $qIndex;
                
                $data->{'sceQueues'}{$pIndex}{$qIndex} =
                    $txQueueDesc->{$oid};
            }
        }
    }

    # Get the names of global service counters

    my $counterNames = $session->get_table
        ( -baseoid => $dd->oiddef('globalScopeServiceCounterName') );

    $devdetails->storeSnmpVars( $counterNames );

    foreach my $gcIndex
        ( $devdetails->getSnmpIndices
          ( $dd->oiddef('globalScopeServiceCounterName') ) )
    {
        my $oid =
            $dd->oiddef('globalScopeServiceCounterName') . '.' . $gcIndex;
        if( length( $counterNames->{$oid} ) > 0 )
        {
            $data->{'sceGlobalCounters'}{$gcIndex} = $counterNames->{$oid};
        }
    }

    return 1;
}


sub buildConfig
{
    my $devdetails = shift;
    my $cb = shift;
    my $devNode = shift;
    my $data = $devdetails->data();

    $cb->addTemplateApplication($devNode, 'CiscoSCE::cisco-sce-common');

    if( $devdetails->hasCap('sceSubscribers') )
    {
        $cb->addTemplateApplication($devNode,
                                    'CiscoSCE::cisco-sce-subscribers');
    }

    # Traffic processors subtree
    
    my $tpNode = $cb->addSubtree( $devNode, 'SCE_TrafficProcessors',
                                  { 'comment' => 'TP usage statistics' },
                                  [ 'CiscoSCE::cisco-sce-tp-subtree']);

    foreach my $tp ( 1 .. $data->{'sceTrafficProcessors'} )
    {
        $cb->addSubtree( $tpNode,
                         sprintf('TP_%d', $tp),
                         { 'sce-tp-index' => $tp },
                         ['CiscoSCE::cisco-sce-tp'] );
    }

    # Queues subtree
    
    my $qNode = $cb->addSubtree( $devNode, 'SCE_Queues',
                                 { 'comment' => 'TX queues usage statistics' },
                                 [ 'CiscoSCE::cisco-sce-queues-subtree']);
    

    foreach my $pIndex ( sort {$a <=> $b} keys %{$data->{'scePortIfIndex'}} )
    {
        my $ifIndex = $data->{'scePortIfIndex'}{$pIndex};
        my $interface = $data->{'interfaces'}{$ifIndex};

        my $portNode =
            $cb->addSubtree( $qNode,
                             $interface->{$data->{'nameref'}{'ifSubtreeName'}},
                             { 'sce-port-index' => $pIndex,
                               'precedence' => 1000 - $pIndex });

        foreach my $qIndex ( sort {$a <=> $b} keys 
                             %{$data->{'sceQueues'}{$pIndex}} )
        {
            my $qName = $data->{'sceQueues'}{$pIndex}{$qIndex};
            my $subtreeName = 'Q' . $qIndex;
            
            $cb->addLeaf( $portNode, $subtreeName,
                          { 'sce-queue-index' => $qIndex,
                            'comment' => $qName,
                            'precedence' => 1000 - $qIndex });
        }
    }

    # Global counters

    foreach my $linkIndex ( 1 .. $data->{'sceInfo'}{'pmoduleNumLinks'} )
    {
        my $gcNode =
            $cb->addSubtree
            ( $devNode, 'SCE_Global_Counters_L' . $linkIndex,
              { 'comment' => 'Global service counters for link #' . $linkIndex
                },
              [ 'CiscoSCE::cisco-sce-gc-subtree']);
        
        foreach my $gcIndex
            ( sort {$a <=> $b}
              keys %{$data->{'sceGlobalCounters'}} )
        {
            my $srvName = $data->{'sceGlobalCounters'}{$gcIndex};
            my $subtreeName = $srvName;
            $subtreeName =~ s/\W/_/g;
            
            $cb->addSubtree( $gcNode, $subtreeName,
                             { 'sce-link-index' => $linkIndex,
                               'sce-gc-index' => $gcIndex,
                               'comment' => $srvName,
                               'sce-service-name' => $srvName,
                               'precedence' => 1000 - $gcIndex},
                             [ 'CiscoSCE::cisco-sce-gcounter' ]);
        }
    }
}

1;

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
