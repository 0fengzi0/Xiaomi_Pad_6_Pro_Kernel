#!/usr/bin/env python3
"""Exercise the actual PTE walker with mocked page-table/locking primitives.

Run on Linux with a host C compiler. This is a control-flow regression test,
not an MMU, concurrency or device test. --baseline optionally checks that the
unpatched memory.c reproduces the regression before testing the working tree.
"""

import argparse
from pathlib import Path
import subprocess


PREFIX = r"""
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#define PAGE_SIZE 4096UL
#define PGTBL_PTE_MODIFIED 1U
#define BUG_ON(condition) do { if (condition) abort(); } while (0)
typedef unsigned long pte_t;
typedef unsigned long pmd_t;
typedef unsigned int pgtbl_mod_mask;
typedef int spinlock_t;
typedef int (*pte_fn_t)(pte_t *, unsigned long, void *);
struct mm_struct { int unused; };
static struct mm_struct init_mm;
static pte_t entries[4];
static spinlock_t fake_lock;
static pte_t *pte_offset_kernel(pmd_t *pmd, unsigned long addr)
{ (void)pmd; return entries + addr / PAGE_SIZE; }
static pte_t *pte_alloc_kernel_track(pmd_t *pmd, unsigned long addr,
                                    pgtbl_mod_mask *mask)
{ (void)mask; return pte_offset_kernel(pmd, addr); }
static pte_t *pte_offset_map_lock(struct mm_struct *mm, pmd_t *pmd,
                                unsigned long addr, spinlock_t **lock)
{ (void)mm; *lock = &fake_lock; return pte_offset_kernel(pmd, addr); }
#define pte_alloc_map_lock pte_offset_map_lock
static bool pmd_huge(pmd_t pmd) { (void)pmd; return false; }
static bool pte_none(pte_t pte) { return pte == 0; }
static void arch_enter_lazy_mmu_mode(void) {}
static void arch_leave_lazy_mmu_mode(void) {}
static void pte_unmap_unlock(pte_t *pte, spinlock_t *lock)
{ (void)pte; (void)lock; }
"""

SUFFIX = r"""
struct visit_log { unsigned int count; unsigned long addresses[4]; int fail_at; };
static int visit(pte_t *pte, unsigned long addr, void *data)
{
    struct visit_log *log = data;
    if (pte != entries + addr / PAGE_SIZE || log->count >= 4)
        return -EINVAL;
    log->addresses[log->count++] = addr;
    return log->fail_at && log->count == (unsigned int)log->fail_at ? -EIO : 0;
}
static int scenario(const char *name, bool create, bool leading_hole,
                    int fail_at, unsigned int expected_count)
{
    pmd_t pmd = 0;
    pgtbl_mod_mask mask = 0;
    struct visit_log log = { .fail_at = fail_at };
    entries[0] = leading_hole ? 0 : 1;
    entries[1] = leading_hole ? 1 : 0;
    entries[2] = 1;
    entries[3] = 0;
    int result = apply_to_pte_range(&init_mm, &pmd, 0, 4 * PAGE_SIZE,
                                    visit, &log, create, &mask);
    if (result != (fail_at ? -EIO : 0) || log.count != expected_count ||
        !(mask & PGTBL_PTE_MODIFIED)) {
        printf("FAIL %s: result=%d callbacks=%u\n", name, result, log.count);
        return 1;
    }
    if (!create && !fail_at &&
        (log.addresses[0] != (leading_hole ? PAGE_SIZE : 0) ||
         log.addresses[1] != 2 * PAGE_SIZE)) {
        printf("FAIL %s: wrong callback addresses\n", name);
        return 1;
    }
    printf("PASS %s\n", name);
    return 0;
}
int main(void)
{
    int failures = 0;
    failures += scenario("existing mappings after leading hole", false, true, 0, 2);
    failures += scenario("existing mappings after middle hole", false, false, 0, 2);
    failures += scenario("create visits every entry", true, true, 0, 4);
    failures += scenario("callback failure stops walk", true, true, 1, 1);
    return failures ? 1 : 0;
}
"""


def extract_function(source):
    start = source.index("static int apply_to_pte_range(")
    end = source.index("\nstatic int apply_to_pmd_range(", start)
    return source[start:end]


def exercise(source, name, output_dir, compiler):
    generated = output_dir / (name + ".c")
    executable = output_dir / name
    generated.write_text(PREFIX + extract_function(source) + SUFFIX, encoding="utf-8")
    subprocess.run([compiler, "-std=gnu11", "-Wall", "-Wextra", "-Werror",
                    str(generated), "-o", str(executable)], check=True)
    return subprocess.run([str(executable)], check=False).returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--cc", default="cc")
    arguments = parser.parse_args()
    project = Path(__file__).resolve().parents[2]
    output_dir = project / "work/dependencies/maintenance/pte-test"
    output_dir.mkdir(parents=True, exist_ok=True)
    if arguments.baseline:
        result = exercise(arguments.baseline.read_text(), "baseline", output_dir,
                          arguments.cc)
        if result != 1:
            raise RuntimeError("Baseline did not reproduce the expected regression")
        print("Baseline regression reproduced", flush=True)
    result = exercise((project / "mm/memory.c").read_text(), "patched", output_dir,
                      arguments.cc)
    if result != 0:
        raise RuntimeError("Patched PTE walk regression test failed")
    print("PASS: four control-flow scenarios; MMU/locks are mocked.")


if __name__ == "__main__":
    main()
