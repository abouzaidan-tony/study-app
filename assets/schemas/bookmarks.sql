

------------
--BOOKMARK--
------------
--store each bookmark
create table bookmark (
    id integer primary key autoincrement,
    date date not null,
    book_id int not null,
    chapter int not null,
    from_verse int not null,
    to_verse int not null
);

CREATE INDEX idx_bookmark_book_chapter
ON bookmark(book_id, chapter);
