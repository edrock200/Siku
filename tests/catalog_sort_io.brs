' SPDX-License-Identifier: AGPL-3.0-or-later
' Test-only wrappers for tests/test_catalog_sort.py: CatalogSort_options as plain id / label lists.

function CatalogSortT_ids(relevance as string, personalized as boolean, shown as dynamic, keep as dynamic) as object
    out = []
    for each o in CatalogSort_options(relevance, personalized, shown, keep)
        out.Push(o.id)
    end for
    return out
end function

function CatalogSortT_labels(relevance as string, personalized as boolean, shown as dynamic, keep as dynamic) as object
    out = []
    for each o in CatalogSort_options(relevance, personalized, shown, keep)
        out.Push(o.label)
    end for
    return out
end function

function CatalogSortT_defaultDesc(id as string) as dynamic
    for each o in CatalogSort_options("any", true, ["rt_critic", "rt_audience"], "")
        if o.id = id then return o.defaultDesc
    end for
    return invalid
end function
