# -*- coding: utf-8 -*-
"""
Cython linker with C solver
"""

# Author: Remi Flamary <remi.flamary@unice.fr>
#
# License: MIT License

import numpy as np
cimport numpy as np

from ..utils import dist

cimport cython

import warnings


cdef extern from "EMD.h":
    int EMD_wrap(int n1,int n2, double *X, double *Y,double *D, double *G, double* alpha, double* beta, double *cost, int maxIter)
    cdef enum ProblemType: INFEASIBLE, OPTIMAL, UNBOUNDED, MAX_ITER_REACHED


def check_result(result_code):
    if result_code == OPTIMAL:
        return None

    if result_code == INFEASIBLE:
        message = "Problem infeasible. Check that a and b are in the simplex"
    elif result_code == UNBOUNDED:
        message = "Problem unbounded"
    elif result_code == MAX_ITER_REACHED:
        message = "numItermax reached before optimality. Try to increase numItermax."
    warnings.warn(message)
    return message


@cython.boundscheck(False)
@cython.wraparound(False)
def emd_c(np.ndarray[double, ndim=1, mode="c"] a, np.ndarray[double, ndim=1, mode="c"]  b, np.ndarray[double, ndim=2, mode="c"]  M, int max_iter):
    """
        Solves the Earth Movers distance problem and returns the optimal transport matrix

        gamm=emd(a,b,M)

    .. math::
        \gamma = arg\min_\gamma <\gamma,M>_F

        s.t. \gamma 1 = a

             \gamma^T 1= b

             \gamma\geq 0
    where :

    - M is the metric cost matrix
    - a and b are the sample weights

    Parameters
    ----------
    a : (ns,) ndarray, float64
        source histogram
    b : (nt,) ndarray, float64
        target histogram
    M : (ns,nt) ndarray, float64
        loss matrix
    max_iter : int
        The maximum number of iterations before stopping the optimization
        algorithm if it has not converged.


    Returns
    -------
    gamma: (ns x nt) ndarray
        Optimal transportation matrix for the given parameters

    """
    cdef int n1= M.shape[0]
    cdef int n2= M.shape[1]

    cdef double cost=0
    cdef np.ndarray[double, ndim=2, mode="c"] G=np.zeros([n1, n2])
    cdef np.ndarray[double, ndim=1, mode="c"] alpha=np.zeros(n1)
    cdef np.ndarray[double, ndim=1, mode="c"] beta=np.zeros(n2)


    if not len(a):
        a=np.ones((n1,))/n1

    if not len(b):
        b=np.ones((n2,))/n2

    # calling the function
    cdef int result_code = EMD_wrap(n1, n2, <double*> a.data, <double*> b.data, <double*> M.data, <double*> G.data, <double*> alpha.data, <double*> beta.data, <double*> &cost, max_iter)

    return G, cost, alpha, beta, result_code


@cython.boundscheck(False)
@cython.wraparound(False)
def emd_1d_sorted(np.ndarray[double, ndim=1, mode="c"] u_weights,
                  np.ndarray[double, ndim=1, mode="c"] v_weights,
                  np.ndarray[double, ndim=1, mode="c"] u,
                  np.ndarray[double, ndim=1, mode="c"] v,
                  str metric='sqeuclidean'):
    r"""
    Solves the Earth Movers distance problem between sorted 1d measures and
    returns the OT matrix and the associated cost

    Parameters
    ----------
    u_weights : (ns,) ndarray, float64
        Source histogram
    v_weights : (nt,) ndarray, float64
        Target histogram
    u : (ns,) ndarray, float64
        Source dirac locations (on the real line)
    v : (nt,) ndarray, float64
        Target dirac locations (on the real line)
    metric: str, optional (default='sqeuclidean')
        Metric to be used. Only strings listed in :func:`ot.dist` are accepted.
        Due to implementation details, this function runs faster when
        `'sqeuclidean'`, `'cityblock'`,  or `'euclidean'` metrics are used.

    Returns
    -------
    gamma: (n, ) ndarray, float64
        Values in the Optimal transportation matrix
    indices: (n, 2) ndarray, int64
        Indices of the values stored in gamma for the Optimal transportation
        matrix
    cost
        cost associated to the optimal transportation
    """
    cdef double cost = 0.
    cdef int n = u_weights.shape[0]
    cdef int m = v_weights.shape[0]

    cdef int i = 0
    cdef double w_i = u_weights[0]
    cdef int j = 0
    cdef double w_j = v_weights[0]

    cdef double m_ij = 0.

    cdef np.ndarray[double, ndim=1, mode="c"] G = np.zeros((n + m - 1, ),
                                                           dtype=np.float64)
    cdef np.ndarray[long, ndim=2, mode="c"] indices = np.zeros((n + m - 1, 2),
                                                              dtype=np.int)
    cdef int cur_idx = 0
    while i < n and j < m:
        if metric == 'sqeuclidean':
            m_ij = (u[i] - v[j]) ** 2
        elif metric == 'cityblock' or metric == 'euclidean':
            m_ij = abs(u[i] - v[j])
        else:
            m_ij = dist(u[i].reshape((1, 1)), v[j].reshape((1, 1)),
                        metric=metric)[0, 0]
        if w_i < w_j or j == m - 1:
            cost += m_ij * w_i
            G[cur_idx] = w_i
            indices[cur_idx, 0] = i
            indices[cur_idx, 1] = j
            i += 1
            w_j -= w_i
            w_i = u_weights[i]
        else:
            cost += m_ij * w_j
            G[cur_idx] = w_j
            indices[cur_idx, 0] = i
            indices[cur_idx, 1] = j
            j += 1
            w_i -= w_j
            w_j = v_weights[j]
        cur_idx += 1
    return G[:cur_idx], indices[:cur_idx], cost
