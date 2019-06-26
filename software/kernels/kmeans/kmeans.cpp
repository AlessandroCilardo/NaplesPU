// kmeans.c
// Ethan Brodsky
// October 2011

#include <math.h>
#include <stdlib.h>
#include "data.h"

#ifndef NUPLUS_ACCELERATOR
#include <stdio.h>
#endif

#define sqr(x) ((x) * (x))

#define MAX_CLUSTERS 16
#define MAX_ITERATIONS 100

#ifndef NUPLUS_ACCELERATOR
#define BIG_float (INFINITY)
#else
#define BIG_float (0x7f800000)
#endif

#ifdef NUPLUS_ACCELERATOR
#define CORE_ID     __builtin_nuplus_read_control_reg(0)
#define THREAD_ID   __builtin_nuplus_read_control_reg(2)
#define CORE_NUMB   1
#define THREAD_NUMB 1
#else
#define CORE_ID     0  
#define THREAD_ID   0
#define CORE_NUMB   1
#define THREAD_NUMB 1
#endif

void fail(char *str)
{
#ifndef NUPLUS_ACCELERATOR
  printf("%s", str);
  exit(-1);
#endif
}

float calc_distance(int dim, float *p1, float *p2)
{
  float distance_sq_sum = 0;

  for (int ii = 0; ii < dim; ii++)
    distance_sq_sum += sqr(p1[ii] - p2[ii]);

  return distance_sq_sum;
}

void calc_all_distances(int dim, int n, int k, float *X, float *centroid, float *distance_output)
{
  for (int ii = CORE_ID; ii < n; ii += CORE_NUMB)       // for each point
    for (int jj = THREAD_ID; jj < k; jj += THREAD_NUMB) // for each cluster
    {
      // calculate distance between point and cluster centroid
      distance_output[ii * k + jj] = calc_distance(dim, &X[ii * dim], &centroid[jj * dim]);
    }
#ifdef NUPLUS_ACCELERATOR
  //__builtin_nuplus_barrier(CORE_ID * 100 + 1, THREAD_NUMB - 1);
#endif
}

float calc_total_distance(int dim, int n, int k, float *X, float *centroids, int *cluster_assignment_index)
// NOTE: a point with cluster assignment -1 is ignored
{
  static float tot_D = 0;

  // for every point
  for (int ii = CORE_ID; ii < n; ii += CORE_NUMB)
  {
    // which cluster is it in?
    if (THREAD_ID == 0)
    {
      int active_cluster = cluster_assignment_index[ii];

      // sum distance
      if (active_cluster != -1)
        tot_D += calc_distance(dim, &X[ii * dim], &centroids[active_cluster * dim]);
    }
  }

  return tot_D;
}

void choose_all_clusters_from_distances(int dim, int n, int k, float *distance_array, int *cluster_assignment_index)
{
  // for each point
  for (int ii = CORE_ID; ii < n; ii += CORE_NUMB)
  {
    int best_index = -1;
    float closest_distance = BIG_float;

    // for each cluster
    for (int jj = THREAD_ID; jj < k; jj += THREAD_NUMB)
    {
      // distance between point and cluster centroid

      float cur_distance = distance_array[ii * k + jj];
      if (cur_distance < closest_distance)
      {
        best_index = jj;
        closest_distance = cur_distance;
      }
    }

    // record in array
    cluster_assignment_index[ii] = best_index;
  }
#ifdef NUPLUS_ACCELERATOR
  //__builtin_nuplus_barrier(CORE_ID * 100 + 3, THREAD_NUMB - 1);
#endif
}

void calc_cluster_centroids(int dim, int n, int k, float *X, int *cluster_assignment_index, float *new_cluster_centroid)
{
  int cluster_member_count[MAX_CLUSTERS];

  // initialize cluster centroid coordinate sums to zero
  for (int ii = CORE_ID; ii < k; ii += CORE_NUMB)
  {
    cluster_member_count[ii] = 0;

    for (int jj = THREAD_ID; jj < dim; jj += THREAD_NUMB)
      new_cluster_centroid[ii * dim + jj] = 0;
  }

  // sum all points
  // for every point
  for (int ii = CORE_ID; ii < n; ii += CORE_NUMB)
  {
    // which cluster is it in?
    int active_cluster = cluster_assignment_index[ii];

    // update count of members in that cluster
    cluster_member_count[active_cluster]++;

    // sum point coordinates for finding centroid
    for (int jj = THREAD_ID; jj < dim; jj += THREAD_NUMB)
      new_cluster_centroid[active_cluster * dim + jj] += X[ii * dim + jj];
  }

  // now divide each coordinate sum by number of members to find mean/centroid
  // for each cluster
  for (int ii = 0; ii < k; ii++)
  {
#ifndef NUPLUS_ACCELERATOR
    if (cluster_member_count[ii] == 0)
      printf("WARNING: Empty cluster %d! \n", ii);
#endif
    // for each dimension
    for (int jj = THREAD_ID; jj < dim; jj += THREAD_NUMB)
      new_cluster_centroid[ii * dim + jj] /= cluster_member_count[ii]; /// XXXX will divide by zero here for any empty clusters!
  }
}

void get_cluster_member_count(int n, int k, int *cluster_assignment_index, int *cluster_member_count)
{
  // initialize cluster member counts
  for (int ii = CORE_ID; ii < k; ii += CORE_NUMB)
    if (THREAD_ID == 0)
      cluster_member_count[ii] = 0;

  // count members of each cluster
  for (int ii = CORE_ID; ii < n; ii += CORE_NUMB)
    if (THREAD_ID == 0)
      cluster_member_count[cluster_assignment_index[ii]]++;

#ifdef NUPLUS_ACCELERATOR
    //__builtin_nuplus_barrier(CORE_ID * 100 + 15, THREAD_NUMB - 1);
#endif
}

void update_delta_score_table(int dim, int n, int k, float *X, int *cluster_assignment_cur, float *cluster_centroid, int *cluster_member_count, float *point_move_score_table, int cc)
{
  // for every point (both in and not in the cluster)
  for (int ii = CORE_ID; ii < n; ii += CORE_NUMB)
  {
    float dist_sum = 0;
    for (int kk = THREAD_ID; kk < dim; kk += THREAD_NUMB)
    {
      float axis_dist = X[ii * dim + kk] - cluster_centroid[cc * dim + kk];
      dist_sum += sqr(axis_dist);
    }

    float mult = ((float)cluster_member_count[cc] / (cluster_member_count[cc] + ((cluster_assignment_cur[ii] == cc) ? -1 : +1)));

    point_move_score_table[ii * dim + cc] = dist_sum * mult;

#ifdef NUPLUS_ACCELERATOR
    //__builtin_nuplus_barrier(CORE_ID * 100 + 9, THREAD_NUMB - 1);
#endif
  }
}

void perform_move(int dim, int n, int k, float *X, int *cluster_assignment, float *cluster_centroid, int *cluster_member_count, int move_point, int move_target_cluster)
{
  int cluster_old = cluster_assignment[move_point];
  int cluster_new = move_target_cluster;

  // update cluster assignment array
  cluster_assignment[move_point] = cluster_new;

  // update cluster count array
  cluster_member_count[cluster_old]--;
  cluster_member_count[cluster_new]++;

#ifndef NUPLUS_ACCELERATOR
  if (cluster_member_count[cluster_old] <= 1)
    printf("WARNING: Can't handle single-member clusters! \n");
#endif
  // update centroid array
  for (int ii = CORE_ID; ii < dim; ii += CORE_NUMB)
  {
    if (THREAD_ID == 0)
    {
      cluster_centroid[cluster_old * dim + ii] -= (X[move_point * dim + ii] - cluster_centroid[cluster_old * dim + ii]) / cluster_member_count[cluster_old];
      cluster_centroid[cluster_new * dim + ii] += (X[move_point * dim + ii] - cluster_centroid[cluster_new * dim + ii]) / cluster_member_count[cluster_new];
    }
  }

#ifdef NUPLUS_ACCELERATOR
  //__builtin_nuplus_barrier(CORE_ID * 100 + 10, THREAD_NUMB - 1);
#endif
}

void cluster_diag(int dim, int n, int k, float *X, int *cluster_assignment_index, float *cluster_centroid)
{
  int cluster_member_count[MAX_CLUSTERS];

  get_cluster_member_count(n, k, cluster_assignment_index, cluster_member_count);

#ifndef NUPLUS_ACCELERATOR
  //printf("  Final clusters \n");
  //for (int ii = 0; ii < k; ii++)
  //  printf("    cluster %d:     members: %8d, centroid (%.1f %.1f) \n", ii, cluster_member_count[ii], cluster_centroid[ii * dim + 0], cluster_centroid[ii * dim + 1]);
#endif
}

void copy_assignment_array(int n, int *src, int *tgt)
{
  for (int ii = CORE_ID; ii < n; ii += CORE_NUMB)
    if (THREAD_ID == 0)
      tgt[ii] = src[ii];
}

int assignment_change_count(int n, int a[], int b[])
{
  int change_count = 0;

  for (int ii = CORE_ID; ii < n; ii += CORE_NUMB)
    if (a[ii] != b[ii])
      change_count++;

#ifdef NUPLUS_ACCELERATOR
  //__builtin_nuplus_barrier(CORE_ID * 100 + 12, THREAD_NUMB - 1);
#endif

  return change_count;
}

int kmeans(
    int dim, // dimension of data

    float *X, // pointer to data
    int n,    // number of elements

    int k,                        // number of clusters
    float *cluster_centroid,      // initial cluster centroids
    int *cluster_assignment_final // output
)
{
  float dist[N * K];
  int cluster_assignment_cur[N];
  int cluster_assignment_prev[N];
  float point_move_score[N * K];

  // initial setup
  calc_all_distances(dim, n, k, X, cluster_centroid, dist);
  choose_all_clusters_from_distances(dim, n, k, dist, cluster_assignment_cur);
  copy_assignment_array(n, cluster_assignment_cur, cluster_assignment_prev);

  // BATCH UPDATE
  float prev_totD = BIG_float;
  int batch_iteration = 0;
  while (batch_iteration < MAX_ITERATIONS)
  {
    //        printf("batch iteration %d \n", batch_iteration);
    //        cluster_diag(dim, n, k, X, cluster_assignment_cur, cluster_centroid);

    // update cluster centroids
    calc_cluster_centroids(dim, n, k, X, cluster_assignment_cur, cluster_centroid);

    // deal with empty clusters
    // XXXXXXXXXXXXXX

    // see if we've failed to improve
    float totD = calc_total_distance(dim, n, k, X, cluster_centroid, cluster_assignment_cur);
    if (totD > prev_totD)
    // failed to improve - currently solution worse than previous
    {
      // restore old assignments
      copy_assignment_array(n, cluster_assignment_prev, cluster_assignment_cur);

      // recalc centroids
      calc_cluster_centroids(dim, n, k, X, cluster_assignment_cur, cluster_centroid);

#ifndef NUPLUS_ACCELERATOR
      //printf("  negative progress made on this step - iteration completed (%.2f) \n", totD - prev_totD);
#endif
      // done with this phase
      break;
    }

    // save previous step
    copy_assignment_array(n, cluster_assignment_cur, cluster_assignment_prev);

    // move all points to nearest cluster
    calc_all_distances(dim, n, k, X, cluster_centroid, dist);
    choose_all_clusters_from_distances(dim, n, k, dist, cluster_assignment_cur);

    int change_count = assignment_change_count(n, cluster_assignment_cur, cluster_assignment_prev);

#ifndef NUPLUS_ACCELERATOR
    //printf("%3d   %u   %9d  %16.2f %17.2f\n", batch_iteration, 1, change_count, totD, totD - prev_totD);
    //fflush(stdout);
#endif

    // done with this phase if nothing has changed
    if (change_count == 0)
    {
#ifndef NUPLUS_ACCELERATOR
      //printf("  no change made on this step - iteration completed \n");
#endif
      break;
    }

    prev_totD = totD;

    batch_iteration++;
  }
#ifdef NUPLUS_ACCELERATOR
  //__builtin_nuplus_barrier(CORE_ID * 100 + 4, THREAD_NUMB - 1);
#endif
  cluster_diag(dim, n, k, X, cluster_assignment_cur, cluster_centroid);

  // write to output array
  copy_assignment_array(n, cluster_assignment_cur, cluster_assignment_final);

  return 0;
}

int main()
{
  int res = 0;

  // start addr = 0x800000, end_addr = 0xFFFFFFFF, valid = 1
  //int mmap = (2 << 11) | (0x3FF << 1) | 1;
  //__builtin_nuplus_write_control_reg(mmap | (THREAD_ID << 21), 19);

  if (THREAD_ID == 0)
    res = kmeans(8, input, 32, 4, input, output);

#ifndef NUPLUS_ACCELERATOR
  //printf("\nOutput:\n");
  for (int i = 0; i < 32; i++)
  {
    printf("%d\t", output[i]);
    if (((i + 1) % 16) == 0)
      printf("\n");
  }
  printf("\n");
  return 0;
#else
  if (THREAD_ID == 0){
    for (int i = CORE_ID; i < 32; i++)
    {
      __builtin_nuplus_flush((int)&output[i]);
    }
    __builtin_nuplus_write_control_reg(32, 12); // For cosimulation purpose
  }
  return (int)&output[0];
#endif
}