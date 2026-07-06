

------------
--BOOKMARK--
------------
--store each bookmark
create table bookmark (
    id integer primary key autoincrement,
    date date not null,
    book_id int not null,
    chapter int not null,
    verse int not null
);

CREATE INDEX idx_bookmark_book_chapter
ON bookmark(book_id, chapter);

------------
--HIGHLIGHT--
------------
--store each highlight
create table highlight (
    id integer primary key autoincrement,
    date date not null,
    book_id int not null,
    chapter int not null,
    from_word int not null,
    to_word int not null,
    color_idx int not null
);

CREATE INDEX idx_highlight_book_chapter
ON highlight(book_id, chapter);
