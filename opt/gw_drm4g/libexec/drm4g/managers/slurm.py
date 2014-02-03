import re
import drm4g.managers 
from string import Template

__version__  = '1.0'
__author__   = 'Carlos Blanco'
__revision__ = "$Id: slurm.py 1980 2014-01-26 10:58:25Z carlos $"

# The programs needed by these utilities. If they are not in a location
# accessible by PATH, specify their location here.
SBATCH  = 'sbatch'   #submit a job
SQUEUE  = 'squeue'   #show status of jobs
SCANCEL = 'scancel'  #delete a job

class Resource (drm4g.managers.Resource):
    pass

class Job (drm4g.managers.Job):
   
    #job status <--> GridWay job status
    states_SLURM = {'CANCELLED': 'DONE', 
                  'COMPLETED' : 'DONE', 
                  'COMPLETING': 'ACTIVE',  
                  'RUNNING'   : 'ACTIVE',  
                  'NODE_FAIL' : 'FAILED',  
                  'FAILED'    : 'FAILED',
                  'PENDING'   : 'PENDING',  
                  'SUSPENDED' : 'SUSPENDED',
                  'TIMEOUT'   : 'FAILED',
                }
    
    def jobSubmit(self, pathScript):
        out, err = self.Communicator.execCommand('%s %s' % (SBATCH, pathScript))
        re_job_id = re.compile(r'Submitted batch job (\d*)').search(out)
        if re_job_id:
            return re_job_id.group(1)
        else:
            raise drm4g.managers.JobException(' '.join(err.split('\n')))        

    def jobStatus(self):
        out, err = self.Communicator.execCommand('squeue -h -o %T -j ' + self.JobId)
        if err:
            return 'UNKNOWN'
        elif not out:
            return 'DONE'
        else:
            return self.states_SLURM.setdefault(out.rstrip('\n'), 'UNKNOWN')
    
    def jobCancel(self):
        out, err = self.Communicator.execCommand('%s %s' % (SCANCEL, self.JobId))
        if err: 
            raise drm4g.managers.JobException(' '.join(err.split('\n')))

    def jobTemplate(self, parameters):
        args  = '#!/bin/bash\n'
        args += '#SBATCH --job-name=JID_%s\n' % (parameters['environment']['GW_JOB_ID'])
        args += '#SBATCH --output=$stdout\n'
        args += '#SBATCH --error=$stderr\n'
        if parameters['queue'] != 'default':
            args += '#SBATCH -p $queue\n'
        if parameters.has_key('maxWallTime'): 
            args += '#SBATCH --time=%s\n' % (parameters['maxWallTime'])
        if parameters.has_key('maxMemory'):
            args += '#SBATCH --mem=%s\n' % (parameters['maxMemory'])
        if parameters.has_key('ppn'): 
            args += '#SBATCH --ntasks-per-node=$ppn'
        if parameters.has_key('nodes'): 
            args += '#SBATCH --nodes=$nodes'
        args += '#SBATCH --ntasks=$count\n'
        args += ''.join(['export %s=%s\n' % (k, v) for k, v in parameters['environment'].items()])
        args += '\n'
        args += '$executable\n'
        return Template(args).safe_substitute(parameters)

