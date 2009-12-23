#!/usr/bin/env python

import os, sys
import subprocess

def debug(text):
    print("------>>>  " + str(text))
    
    
class NotImplementedException(Exception):
    pass

class AB:
    """AlienBrain command line tool wrapper, to get data easier with scripting,
    The API design will mimic the ones of Perforce, see: 'Perforce 2009.1 APIs 
    for Scripting' """
    # Q: is it a good way to parse stdout, stderr?
    
    # 'long  => short' command name mapping, used in checking or validation
    AB_CMDS = { }
    
    VALID_ARGS = ("get")
    
    session = None  # obj must have sth. to record.
    auto_reconnect = True
    
    def __init__(self, executable):
        self.executable =  executable
        # TODO: check version info
        self.args = []
        self.output = ""
    
    def getworkingpath(self):
        self.args = []
        self.args.extend("getworkingpath")
        self.call()
        return self.output
    
#    def call(self):
#        self.output = os.popen(self.executable + " " + " ".join(self.args) ).read()
#        return self.output
        
        
    # ESP.TODO: use meta programming to generate commands from syntax knowledge,
    # e.g. getworkingpath call should be validated and sent to msg receiver.
    
#    def cmd(self, cmd_string):
#        """ simply get stdout and stderr from executing a commandline, it seems the result
#        parsing should be done by the each caller."""
#        proc = subprocess.Popen(cmd_string,
#                        shell=True,
#                        stdin=subprocess.PIPE,
#                        stdout=subprocess.PIPE,
#                        stderr=subprocess.PIPE,
#                        )
#        
#        stdout_value, stderr_value = proc.communicate()
#        print(stdout_value + " <<<= stdout")
#        print(stderr_value + " <<<= stderr")
        
    # Q: how to get output and return value simultaneously
    # INFO: it's an example of using subprocess.call()
    def call_using_subproc(self, cmd_string):
        """"""
        debug(cmd_string)
        retcode = subprocess.call(cmd_string, shell=True, stdin=PIPE)
        out = sys.stdout.readlines()
        err = sys.stderr.readlines()
        debug("return code " + str(retcode))
        debug(out) 
        debug(err)
        #debug(sys.__stderr__.readlines())
        return (retcode, sys.stdout, sys.stderr)
        
    # INFO, 
    def call(self,cmd_string):
        debug(cmd_string)
        process = subprocess.Popen(cmd_string, shell=True, stdin=subprocess.PIPE, 
                                   stdout=subprocess.PIPE )
        (child_stdout, child_stdin) = (process.stdout, process.stdin)
#        out = sys.stdout.readlines()
#        err = sys.stderr.readlines()
#        debug(out) 
        debug(child_stdout.readlines())
        
        process.stdin.close()
        val = process.wait()
        if  val != 0:
            print "There were some errors(not error really!) , wait returns %s"  % val
    
    # damned, it should be generated from documentation or self-help.
    def logon(self, username, password, project, ab_server):
        cmd_str = " ".join(['ab', 'logon','-u', username, '-p',password, '-d', project, '-s', ab_server])
        self.call(cmd_str)
    
    def logoff(self): 
        cmd_str = " ".join(['ab','logoff'])
        self.call(cmd_str)
        
    def connected(self):
        cmd_str = " ".join(['ab','ic'])
        self.call(cmd_str)
    
    def setworkingpath(self,dir):
        #TODO: avoid blankspace and slash '\'
        cmd_str = " ".join(['ab','setworkingpath',dir])
        self.call(cmd_str)    
        
    def getworkingpath(self):
        #TODO: avoid blankspace and slash '\'
        cmd_str = " ".join(['ab','getworkingpath'])
        self.call(cmd_str)
    
    def p4_workspace_dir(self, dir_in_depot, view):
        """ map the //depot... to local directory from a preset view of p4 workspace"""
        
        # template replace
        # TODO: see if neccessary!
        map_depot_to_local_dir = {}
        if type(view)  == type(dict()):
            # parse the multiple line of view mapping, hopefully each entry is on the just one line.
            lines = view.split("\n")
            
            for line in lines:
                (key, value ) = line.split(" ")
                key = key.strip()       #remove heading/trailing spaces 
                if key.startswith("+"): #remove multiple line view symbol "+"
                    key = key[1:]
        return 
        
        
    
    def apply_actions(self, p4_chg_detail):
        """ add, edit, delete files according to an perforce change info"""
        # validation of p4_chg, TODO: more strict check
        if len(p4_chg_detail['depotFile']) != len(p4_chg_detail['action']):
            raise "p4_chg corrupted, could not be migrate to Alienbrain"
        
        #Q: how to know the local directory of a file from //depot without view mapping info? 
        for i in range(0, len(p4_chg_detail['action']) ):
            file = p4_chg_detail['depotFile'][i]  
            debug("file: %s \n" %  file )
            action = p4_chg_detail['action'][i]
            debug("action: %s \n" % action )
            localdir = self.p4_workspace_dir(file, p4env['view']) 
            debug ("local dir is : %s \n " % localdir )
                
    def submit_file(self,file):    
        pass
    
    def submit_change():
        """submit changes on the workspace after calling an p4 sync"""
        #TODO: sanity check to prevent the interrupted one or duplicated one! 
        #TODO: ??make it atomic? rollback ab's change if not fulfilled.  
        pass
    
    
#if __name__ == '__main__':
#    ab = AB("C:\Program Files (x86)\alienbrain\Client\Application\Tools\ab.exe")
#    print(ab.getworkingpath())

# ESP. COMMMANDS

## log on
#ab logon -u Administrator -p "mes0Spicy" -d p4mirror -s Spicyfile


## setup ab local workspace, ready to import changeSet
#ab -


## add file
#ab 



#Usage Examples:
#---------------
#ab help checkout
#ab h gl
#ab enumprojects -s NXNSERVER
#ab logon -u John -p "" -d Demo_Project -s NXNSERVER
#ab setworkingpath "c:\myworkingpath\Demo_Project"
#ab enumobjects
#ab isuptodate picture1.bmp
#ab find -checkedoutby "John"
#ab checkout picture1.bmp -comment "Modifying background" -response:CheckOut.Writ
#able y
#ab logoff

import P4
import os
from operator import itemgetter
import operator


#TODO: logging

p4env = {
    'port':'localhost:1666',
    'user':'ZhuJiaCheng',
    'passwd':'',
    'client':'ZhuJiaCheng_test_specify_p4_env',
    'branch':'',
    'charset':'',
    #'customview':'''View:
    'view':'''
    //depot/Alice2_Prog/Development/... //ZhuJiaCheng_test_specify_p4_env/Development/...
    +//depot/Alice2_Prog/Tools/... //ZhuJiaCheng_test_specify_p4_env/Tools/...
    +//depot/Alice2_Bin/PC_Dependencies/... //ZhuJiaCheng_test_specify_p4_env/PC_Dependencies/...
    +//depot/Alice2_Bin/Binaries/... //ZhuJiaCheng_test_specify_p4_env/Binaries/...
    +//depot/Alice2_Bin/Engine/... //ZhuJiaCheng_test_specify_p4_env/Engine/...
    +//depot/Alice2_Bin/AliceGame/... //ZhuJiaCheng_test_specify_p4_env/AliceGame/...
    +//depot/Alice2_Bin/*.* //ZhuJiaCheng_test_specify_p4_env/*.*
    +//depot/Alice2_Branches/... //ZhuJiaCheng_test_specify_p4_env/Alice2_Branches/...
''',
    # depre: 'workspace' : 'Admin_spicyfile_1666_NightlySlave',  # => buildbot auto-generated by rules
    }


p4 = P4.P4()
#ab = AB.AB()




def p4_init():

    p4.client = p4env['client']
    p4.port = p4env['port']
    p4.user = p4env['user']
    p4.password = p4env['passwd']
    #p4.charset = p4env['charset']
    #TODO: lock format by setting API level!!!
    p4.exception_level = 1 # ignore "File(s) up-to-date"
    if not p4.connected(): p4.connect() 
    return p4
#    except P4Exception:
#        for e in p4.errors:
#            print e
#    finally:
#        p4.disconnect()
        
def change_workdir(dir):
    """ change to the desired the directory for migration, in case of
    any undesired default directory."""
    p4 = p4_init()
    clientspec = p4.fetch_client()
    if os.path.exists(dir):
        clientspec['Root'] = dir
    p4.save_client(clientspec)  


def p4_get_changes():
    p4 = p4_init() 
    changes = []
    
    # TODO: see if need to get branch related changelist, it looks like 
    #  for a2, no way to get changelists from branch info.
    try:
        changes = p4.run('changes', '-t', '-l')
    except P4Exception:
        for e in p4.errors:
            print e
            debug(e)
        #TODO: log here

    deco = [( int(change['change']), change) for change in changes ]
    deco.sort()
    changes = [ change for (key, change) in deco]
    debug(changes[0].__class__)
    debug(changes[0])
    debug(changes[1])
    debug(changes[0]['desc'])
    debug(changes[0]['time'])
    debug(changes[0].keys())
    
    return changes
    

def p4_get_change_details(change):
    change_num = change['change'];
    debug( "ready to get detail of changelist %s \n " % str(change_num))
    debug("p4_get_change_details: %s \n" % str(change_num) );
    p4 = p4_init();
    detail = p4.run('describe', '-s', change_num);
    print detail[0]
       
    return detail[0]   
#    raise "stop here"
#    error_count = p4.ErrorCount();
#    errors = p4.Errors();
#    p4.Disconnect();
#    if error_count:
#        debug("Skipping $change_num due to errors:\n$errors\n")
#    return undef;
#    
#    my %result;
#    result['author'] = change->{'user'};
#    result{'log'}  = change->{'desc'};
#    result{'date'} = time2str(SVN_DATE_TEMPLATE, change->{'time'});
#    for (my i = 0; i < @{change->{'depotFile'}}; i++) {
#    my file = change->{'depotFile'}[i];
#    my action = change->{'action'}[i];
#    my type = change->{'type'}[i];
#    if (is_wanted_file(file)) {
#        push @{result{'actions'}}, {'action' => action,
#                                     'path' => file,
#                                     'type' => type};  
#    
    
    
    
if __name__ == '__main__':   
    # -----------------------  ab sandbox
    
    ab = AB("C:/Program Files (x86)/alienbrain/Client/Application/Tools/ab.exe")
#    
#    ab.logon("Administrator", "mes0Spicy", "p4migtest ", "Spicyfile")
#    ab.getworkingpath()
#    ab.setworkingpath("d:/p4migtest")
#    ab.getworkingpath()
#    ab.connected()
#    ab.logoff()
#    ab.connected()
#    print "end of commands"


    # ---------------------- p4 sandbox
    #p4_get_changes()[0]
    
    #change_workdir("D:/p4migtest")
    #p4.run_sync("//depot/...@%s" % "1" )
    changes = p4_get_changes()
    debug("changes size %s"  % str(len(changes)) )
    for change in changes: 
        
        if int(change['change']) == 351:
            debug(" ..... " + str(change['change']) )
            debug("found change 12 \n")
            
            detail = p4_get_change_details(change)
            ab.apply_actions(detail)
            break;

    
    
    
    