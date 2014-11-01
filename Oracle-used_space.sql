select
to_char(CREATION_TIME,'RRRR') year,
to_char(CREATION_TIME,'MM') month,
sum(bytes / 1048576) MBytes
from
v$datafile
group by
to_char(CREATION_TIME,'RRRR'),
to_char(CREATION_TIME,'MM')
order by
1, 2;

select
to_char(CREATION_TIME,'RRRR') year,
to_char(CREATION_TIME,'MM') month,
sum(bytes / 1073741824) GB
from
v$datafile
group by
to_char(CREATION_TIME,'RRRR'),
to_char(CREATION_TIME,'MM')
order by
1, 2;
