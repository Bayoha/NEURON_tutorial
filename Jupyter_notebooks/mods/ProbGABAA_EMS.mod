COMMENT
/**
 * @file ProbGABAA.mod
 * @brief 
 * @author king, muller
 * @date 2011-08-17
 * @remark Copyright © BBP/EPFL 2005-2011; All rights reserved. Do not distribute without further notice.
 */
ENDCOMMENT

TITLE GABAA receptor with presynaptic short-term plasticity 


COMMENT
GABAA receptor conductance using a dual-exponential profile
presynaptic short-term plasticity based on Fuhrmann et al, 2002
Implemented by Srikanth Ramaswamy, Blue Brain Project, March 2009

_EMS (Eilif Michael Srikanth)
Modification of ProbGABAA: 2-State model by Eilif Muller, Michael Reimann, Srikanth Ramaswamy, Blue Brain Project, August 2011
This new model was motivated by the following constraints:

1) No consumption on failure.  
2) No release just after release until recovery.
3) Same ensemble averaged trace as deterministic/canonical Tsodyks-Markram 
   using same parameters determined from experiment.
4) Same quantal size as present production probabilistic model.

To satisfy these constaints, the synapse is implemented as a
uni-vesicular (generalization to multi-vesicular should be
straight-forward) 2-state Markov process.  The states are
{1=recovered, 0=unrecovered}.

For a pre-synaptic spike or external spontaneous release trigger
event, the synapse will only release if it is in the recovered state,
and with probability u (which follows facilitation dynamics).  If it
releases, it will transition to the unrecovered state.  Recovery is as
a Poisson process with rate 1/Dep.

This model satisys all of (1)-(4).


ENDCOMMENT


NEURON {
    THREADSAFE
	POINT_PROCESS ProbGABAA_EMS
	RANGE tau_r, tau_d
	RANGE Use, u, Dep, Fac, u0, Rstate, tsyn_fac, u
	RANGE i, g, e
	NONSPECIFIC_CURRENT i
    POINTER rng
    RANGE synapseID, verboseLevel
}

PARAMETER {
	tau_r  = 0.2   (ms)  : dual-exponential conductance profile
	tau_d = 8   (ms)  : IMPORTANT: tau_r < tau_d
	Use        = 1.0   (1)   : Utilization of synaptic efficacy (just initial values! Use, Dep and Fac are overwritten by BlueBuilder assigned values) 
	Dep   = 100   (ms)  : relaxation time constant from depression
	Fac   = 10   (ms)  :  relaxation time constant from facilitation
	e    = -80     (mV)  : GABAA reversal potential
    gmax = .001 (uS) : weight conversion factor (from nS to uS)
    u0 = 0 :initial value of u, which is the running value of release probability
    synapseID = 0
    verboseLevel = 0
}

COMMENT
The Verbatim block is needed to generate random nos. from a uniform distribution between 0 and 1 
for comparison with Pr to decide whether to activate the synapse or not
ENDCOMMENT
   
VERBATIM
#include<stdlib.h>
#include<stdio.h>
#include<math.h>

double nrn_random_pick(void* r);
void* nrn_random_arg(int argpos);

ENDVERBATIM
  

ASSIGNED {
	v (mV)
	i (nA)
	g (uS)
	factor
    rng

       : Recording these three, you can observe full state of model
       : tsyn_fac gives you presynaptic times, Rstate gives you 
	 : state transitions,
	 : u gives you the "release probability" at transitions 
	 : (attention: u is event based based, so only valid at incoming events)
       Rstate (1) : recovered state {0=unrecovered, 1=recovered}
       tsyn_fac (ms) : the time of the last spike
       u (1) : running release probability


}

STATE {
	A	: state variable to construct the dual-exponential profile - decays with conductance tau_r
	B	: state variable to construct the dual-exponential profile - decays with conductance tau_d
}

INITIAL{

	LOCAL tp
	A = 0
	B = 0
	tp = (tau_r*tau_d)/(tau_d-tau_r)*log(tau_d/tau_r) :time to peak of the conductance
	factor = -exp(-tp/tau_r)+exp(-tp/tau_d) :Normalization factor - so that when t = tp, gsyn = gpeak
	factor = 1/factor

        Rstate=1
        tsyn_fac=0
        u=u0

}

BREAKPOINT {
	SOLVE state METHOD cnexp
	g = gmax*(B-A) :compute time varying conductance as the difference of state variables B and A
	i = g*(v-e) :compute the driving force based on the time varying conductance, membrane potential, and GABAA reversal
}

DERIVATIVE state{
	A' = -A/tau_r
	B' = -B/tau_d
}


NET_RECEIVE (weight, Psurv, tsyn (ms)){
    LOCAL result

    : Locals:
    : Psurv - survival probability of unrecovered state
    : tsyn - time since last surival evaluation.


    INITIAL{
		tsyn=t
    }

        : calc u at event-
        if (Fac > 0) {
                u = u*exp(-(t - tsyn_fac)/Fac) :update facilitation variable if Fac>0 Eq. 2 in Fuhrmann et al.
           } else {
                  u = Use  
           } 
           if(Fac > 0){
                  u = u + Use*(1-u) :update facilitation variable if Fac>0 Eq. 2 in Fuhrmann et al.
           }    

	   : tsyn_fac knows about all spikes, not only those that released
	   : i.e. each spike can increase the u, regardless of recovered state.
	   tsyn_fac = t

	   : recovery

	   if (Rstate == 0) {
	   : probability of survival of unrecovered state based on Poisson recovery with rate 1/tau
	          Psurv = exp(-(t-tsyn)/Dep)
		  result = urand()
		  if (result>Psurv) {
		         Rstate = 1     : recover      

                         if( verboseLevel > 0 ) {
                             printf( "Recovered! %f at time %g: Psurv = %g, urand=%g\n", synapseID, t, Psurv, result )
                         }

		  }
		  else {
		         : survival must now be from this interval
		         tsyn = t
                         if( verboseLevel > 0 ) {
                             printf( "Failed to recover! %f at time %g: Psurv = %g, urand=%g\n", synapseID, t, Psurv, result )
                         }
		  }
           }	   
	   
	   if (Rstate == 1) {
   	          result = urand()
		  if (result<u) {
		  : release!
   		         tsyn = t
			 Rstate = 0

			 A = A + weight*factor
			 B = B + weight*factor
                         
                         if( verboseLevel > 0 ) {
                             printf( "Release! %f at time %g: vals %g %g %g \n", synapseID, t, A, weight, factor )
                         }
		  		  
		  }
		  else {
		         if( verboseLevel > 0 ) {
			     printf("Failure! %f at time %g: urand = %g\n", synapseID, t, result )
		         }

		  }

	   }

        

}


PROCEDURE setRNG() {
VERBATIM
    {
        /**
         * This function takes a NEURON Random object declared in hoc and makes it usable by this mod file.
         * Note that this method is taken from Brett paper as used by netstim.hoc and netstim.mod
         */
        void** pv = (void**)(&_p_rng);
        if( ifarg(1)) {
            *pv = nrn_random_arg(1);
        } else {
            *pv = (void*)0;
        }
    }
ENDVERBATIM
}

FUNCTION urand() {
VERBATIM
        double value;
        if (_p_rng) {
                /*
                :Supports separate independent but reproducible streams for
                : each instance. However, the corresponding hoc Random
                : distribution MUST be set to Random.uniform(1)
                */
                value = nrn_random_pick(_p_rng);
                //printf("random stream for this simulation = %lf\n",value);
                return value;
        }else{
ENDVERBATIM
                : the old standby. Cannot use if reproducible parallel sim
                : independent of nhost or which host this instance is on
                : is desired, since each instance on this cpu draws from
                : the same stream
                urand = scop_random(1)
VERBATIM
        }
ENDVERBATIM
        urand = value
}

FUNCTION toggleVerbose() {
    verboseLevel = 1 - verboseLevel
}
