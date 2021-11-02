using CSV, DataFrames

const DATADIR = "./ldt_raw";

const SKIPLIST = [  # list of redundant or questionable files
    "9999.LDT",
    "793DATA.LDT",
    "Data999.LDT",
    "Data1000.LDT",
    "Data1010.LDT",
    "Data1016.LDT",
];

"""
    checktbuf(buf::IOBuffer)

Return a DataFrame of the contents of `buf` assuming it contains trial information
"""
function checktbuf(buf)
    return(
        DataFrame(
            CSV.File(
                take!(buf);          # extract contents of and empty buf
                header=[:seq, :itemgrp, :wrd, :acc, :rt, :item],
                comment="=",
                types=[Int16, Int32, Bool, Int8, Int16, String],
            )
        )
    )
end

"""
    skipblanks(strm)

Skip blank lines in strm returning the first non-blank line with `keep=true`
"""
function skipblanks(strm)
    ln = readline(strm; keep=true)
    while isempty(strip(ln))
        ln = readline(strm; keep=true)
    end
    return ln
end

"""
    parse_ldt_file(fnm)

Return a NamedTuple of `fnm` and 6 DataFrames from LDT file with path `fnm`
"""
function parse_ldt_file(fnm, dir=DATADIR)
    @show fnm
    global univ, sess1, sess2, subj, ncor, hlth
    hdrbuf, trialbuf = IOBuffer(), IOBuffer()        # in-memory "files"
    univhdr = "Univ,Time,Date,Subject,DOB,Education" # occurs in line 1 and after seq 2000
    subjhdr = "Subject,Gender,Task,MEQ,Time,Date"    # marks demog block at file end
    ncorhdr = "numCorrect,rawScore,vocabAge,shipTime,readTime"
    hlthhdr = "presHealth,pastHealth,vision,hearing,firstLang"
    keep = true                                      # pass as named argument to readline
    strm = open(joinpath(dir, fnm), "r")
    ln = readline(strm; keep)
    if !startswith(ln, univhdr)
        throw(ArgumentError("$fnm does not start with expected header"))
    end
    write(hdrbuf, ln)
    write(hdrbuf, readline(strm; keep))
    ln = readline(strm; keep)
    while true     # loop over lines in file
        if startswith(ln, univhdr)   # header for session 2
            write(hdrbuf, readline(strm; keep))   # second line of univ data
            univ = DataFrame(CSV.File(
                take!(hdrbuf);
                types=[Int8, String, String, Int16, String, Int16],
                ),
            )
            sess1 = checktbuf(trialbuf)
        elseif startswith(ln, subjhdr)
            sess2 = checktbuf(trialbuf)
            write(hdrbuf, ln)
            write(hdrbuf, readline(strm; keep))
            subj = DataFrame(CSV.File(
                take!(hdrbuf);
                types=[Int16, String, String, Float32, String, String],
                )
            )
            ln = skipblanks(strm)
            startswith(ln, ncorhdr) || throw(ArgumentError("Expected $ncorhdr, got $ln"))
            write(hdrbuf, ln)
            write(hdrbuf, readline(strm; keep))
            ncor = DataFrame(CSV.File(
                take!(hdrbuf);
                types=[Int8, Int8, Float32, Int8, Float32],
                missingstring="999",
                ),
            )
            ln = skipblanks(strm)
            startswith(ln, hlthhdr) || throw(ArgumentError("Expected $hlthhdr, got $ln"))
            write(hdrbuf, ln)
            write(hdrbuf, readline(strm; keep))
            hlth = DataFrame(CSV.File(
                take!(hdrbuf);
                types=[Int8, Int8, Int8, Int8, String],
                ),
            )
            break
        else
            write(trialbuf, ln)
        end
        ln = readline(strm; keep)
    end
    close(strm)
    return (; fnm, univ, sess1, sess2, subj, ncor, hlth)
end

dfs =
[parse_ldt_file(nm) for nm in filter(∉(SKIPLIST), filter(endswith(r"LDT"i), readdir(DATADIR)))];

function checksubj(nt)
    subjno = only(unique(nt.univ.Subject))
    return only(nt.subj.Subject) == subjno ? subjno : nothing
end

getDOB(nt) = join(unique(nt.univ.DOB), '|')

getEduc(nt) = maximum(nt.univ.Education)
