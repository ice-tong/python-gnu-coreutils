#!/usr/bin/python3
"""
Author: Joshua Chen
Dev dates: from 2015-03-28 to 2015-04-19
Location: Shenzhen

This is a Python version of GNU ls tool, mimic
behaviors of the GNU ls, implemented 27 most
frequently used options out of ls' 61 options,
add one extra option --multi.
"""

import os, sys, stat

prog_path = os.path.realpath(__file__)
prog_dir  = os.path.dirname(prog_path)
sys.path.insert(0, os.path.join(prog_dir, 'lib'))

import builtins
from math import ceil
from system.term import Term
from wcwidth import wcswidth
from pwd import getpwuid
from grp import getgrgid
from time import ctime, localtime, strftime
from itertools import zip_longest

def adjust_blocks(blocks, ls_blksize=1024):
    '''
    ls use a default block size of 1024 bytes, which is not
    the same as the value returned from stat(2)
    '''
    stat_blksize = 512
    return int(blocks / (ls_blksize / stat_blksize))

class Color:
    lfmt = chr(27) + '[%sm' # format of the starting code of a color element
    rfmt = chr(27) + '[0m'  # format of the ending code of a color element

    def __init__(self):
        self.db = os.environ['LS_COLORS'].split(':')

    def get_stat_color(self, mode):
        '''get color according to file stat of the following:
        ORPHAN # symlink to nonexistent file, or non-stat'able file
        SETUID # file that is setuid (u+s)
        SETGID # file that is setgid (g+s)
        CAPABILITY # file with capability (what's this?)
        STICKY_OTHER_WRITABLE # dir that is sticky and other-writable (+t,o+w)
        OTHER_WRITABLE # dir that is other-writable (o+w) and not sticky
        STICKY # dir with the sticky bit set (+t) and not other-writable
        EXEC # file with execute permission:
        stat_keymap = {'or', 'su', 'sg', 'ca', 'tw', 'ow', 'st', 'ex'}

        return the code of the color
        '''
        db = self.db
        res = ''
        # the target of a orphan symlink has no mode element, if a symlink is good,
        # its target will show up as a non-symlink file type, e.g., a directory,
        # a block device.
        if not mode:    # this is a file item of a orphan symlink's target
            res = '37;41;01'    # I could not found this color in dircolors' output
        elif mode[0] == '-':
            if mode[3] in ('s', 'S'):
                res = self.pick_color('su', db)
            elif mode[6] in ('s', 'S'):
                res = self.pick_color('sg', db)
            elif 'x' in (mode[3], mode[6], mode[9]):
                res = self.pick_color('ex', db)
        elif mode[0] == 'd':
            if mode[9] in ('t', 'T'):
                if mode[8] == 'w':
                    res = self.pick_color('tw', db)
                else:
                    res = self.pick_color('st', db)
            elif mode[8] == 'w':
                res = self.pick_color('ow', db)
        return res

    def get_type_color(self, file, mode):
        '''
        get color according to file type, return the code of the color
        '''
        # the target of a orphan link can not be stated, so has no meaningful 'mode'
        if not mode: return ''

        keymap = { '-': 'fi', 'd': 'di', 'l': 'ln',
                        'p': 'pi', 's': 'so', 'b': 'bd', 'c': 'cd' }
        key = keymap[mode[0]]
        res = ''
        if key:
            # it's an orphan symlink
            if key == 'ln':
                if getattr(file, 'target', None) and not getattr(file.target, 'mode', None):
                    key = 'or'
            res = self.pick_color(key, self.db)
        return res

    def get_suffix_color(self, name):
        '''
        get color according to suffix of file name, return the color code
        '''
        res = ''
        arr = name.split('.')
        if len(arr) > 1:
            suffix = arr[-1]
            res = self.pick_color('*.' + suffix, self.db)
        return res

    def make(self, file):
        '''
        make color for the given text using environment variable LS_COLORS
        color the file name in this sequence:
        stat --> type --> suffix
        '''
        db = os.environ['LS_COLORS'].split(':')
        mode = getattr(file, 'mode', None)
        res = self.get_stat_color(mode)
        if not res:
            res = self.get_type_color(file, mode)
            if not res:
                res = self.get_suffix_color(file.name)
        file.color = res
        if getattr(file, 'target', None):
            self.make(file.target)

    def pick_color(self, key, db):
        x = [x for x in db if x.startswith(key + '=')]
        if x:
            return x[0].split('=')[-1]
        else:
            return ''

class FileItem:
    '''
    stores a file's detail information along with some
    methods for data conversion and formating
    '''
    def __init__(self):
        ...

    def __contains__(self, name):
        return name in self.fields

    def symbol_mode(self):
        '''
        convert numeric mode data into symbol string
        '''
        self.mode = stat.filemode(self.mode)

    def uid_to_name(self):
        '''
        convert the numeric uid to user name
        '''
        try:
            u = getpwuid(self.uid)
            self.uid = u.pw_name
        except KeyError: pass

    def gid_to_name(self):
        '''
        convert the numeric gid to group name
        '''
        try:
            g = getgrgid(self.gid)
            self.gid = g.gr_name
        except KeyError: pass

    def human_readable_size(self, size):
        '''
        convert the size represented in bytes to human readable format:
        K: kilobyte
        M: Megabyte
        G: Gigabyte
        T: Terabyte
        P: Petabyte
        E: exabyte
        Z: zettabyte
        Y: yottabyte
        '''
        if size < 1024:
            return str(size)    # zero or less than 1 K

        level = []
        level.append([1024 ** 0, ''])
        level.append([1024 ** 1, 'K'])
        level.append([1024 ** 2, 'M'])
        level.append([1024 ** 3, 'G'])
        level.append([1024 ** 4, 'T'])
        level.append([1024 ** 5, 'P'])
        level.append([1024 ** 6, 'E'])
        level.append([1024 ** 7, 'Z'])
        level.append([1024 ** 8, 'Y'])
        char = ''
        for item, i in zip(level, range(len(level))):
            if size < item[0]:
                item = level[i - 1]
                break

        # 1025 bytes shall be converted to 1.1K
        # so we make it 10 times greater for ceil,
        # then make it 10 times samller
        num = ceil(size * 10 / item[0]) / 10
        return '%s%s' % (num, item[1])

    def format_time(self, key):
        '''
        make time string from time data according to a specific format
        '''
        second = getattr(self, key)
        setattr(self, key, self.timeformater(second))

    def class_indicator(self):
        '''
        make a indicator charactor according to the file type and stat
        '''
        ...

    def adjust_blocks(self, human_readable):
        blocks = adjust_blocks(self.blocks)
        if human_readable:
            blocks = self.human_readable_size(blocks * 1024)
        self.blocks = blocks

    def format(self):
        '''
        format the text of the item for printing
        '''
        assert False, 'must redefine this method'

class LongFormatFileItem(FileItem):
    '''
    class for the file item when do a long format listing
    these options specify long format: -l, -o, -g, -n, --full-time
    default long format includes the following fields:
    mode, nlink, uid, gid, size, time, name.
    -o option removes the 'gid',
    -g option removes the 'uid',
    -n option suppresses the uid and gid translation
    --full-time option make full-iso time format
    '''
    def format(self, formats):
        '''
        format the item info according to the format string
        '''
        text_list = []
        for field_name, format in zip(self.fields, formats):
            text_list.append(format % getattr(self, field_name))
        text_list.append(self.render_name())
        return ' '.join(text_list)

    def render_name(self):
        '''
        color code can be mixed here
        '''
        text = self.name
        if self.consider_color:
            text = Color.lfmt % self.color + text + Color.rfmt
            if getattr(self, 'target', None):
                target_text = Color.lfmt % self.target.color + self.target.name + Color.rfmt
                text = '%s -> %s' % (text, target_text)
        else:
            if getattr(self, 'target', None):
                text = '%s -> %s' % (text, self.target.name)
        return text

class ShortFormatFileItem(FileItem):
    '''
    class for the file item when do a short format listing
    '''
    def format(self, formats):
        '''
        format the item info according to the format string
        '''
        text_list = []
        for field_name, format in zip(self.fields, formats):
            text_list.append(format % getattr(self, field_name))
        text_list.append(self.render_name(formats[-1]))
        return ' '.join(text_list)

    def adjust_width(self, text):
        '''
        given Chinese string '中國人', if we do a '%7s' % '中國人',
        we expect to get ' 中國人', but we actually get back
        '    中國人', because the string formating mechanism
        of Python doesn't take the width of the chars into account,
        they consider one char one column.
        '''
        return wcswidth(text) - len(text)

    def render_name(self, format):
        '''
        color code can be mixed here
        '''
        name = self.name
        if self.consider_color:
            # format string: %-20s
            width = int(format[2:-1])
            lfmt = Color.lfmt % self.color
            width = width + len(lfmt + Color.rfmt) - self.adjust_width(name)
            format = '%-' + str(width) + 's'
            name = lfmt + name + Color.rfmt
        return format % name

class Ls:
    def __init__(self):
        self.parse_args()
        if self.ok_for_color():
            self.color = Color()
        # return status
        self.status = 0

    def parse_args(self):
        '''
        second phase of argument parsing,
        using the result that produced from the argparse module
        '''
        self.args = parse_args()

        # set the default target when none specified
        if not self.args.FILE: self.args.FILE.append(os.path.curdir)

        # detect long format listing
        self.args.long = (self.args.long_format or self.args.no_group
                            or self.args.no_user or self.args.numeric_id
                            or self.args.full_time)

        # which timestamp to use?
        self.args.timestamptype = self.args.timestamptype if 'timestamptype' in self.args else 'mtime'

        # colorize?
        if self.args.color != 'never':
            self.args.color = True
        else:
            self.args.color = False

        # what fields to collect?
        fields = set()
        all_fields = ['ino', 'blocks', 'mode', 'nlink', 'uid',
                              'gid', 'size', 'atime', 'mtime', 'ctime']
        if self.args.sort == 'size': fields |= {'size'}
        if self.args.sort == 'time': fields |= {self.args.timestamptype}
        # need mode for colorizing
        if self.ok_for_color(): fields |= {'mode'}
        if self.args.inode: fields |= {'ino'}
        if self.args.size: fields |= {'blocks'}
        if self.args.long:
            fields |= {'mode', 'nlink', 'uid', 'gid', 'size', self.args.timestamptype}
            if self.args.no_group: fields.remove('gid')
            if self.args.no_user:  fields.remove('uid')
        fields_list = [x for x in all_fields if x in fields]

        # GNU ls's sort by size and time are default descending,
        # and is the reverse of our sorted tool's default, so we reverse it first.
        if self.args.sort in ('size', 'time'): self.args.reverse = not self.args.reverse

        # sorting option -v (version) is not supported
        if self.args.sort == 'version':
            self.args.sort = 'none'

        # time formater
        if self.args.full_time:
            @staticmethod
            def formater(second):
                return strftime('%Y-%m-%d %H:%M:%S', localtime(second))
        else:
            @staticmethod
            def formater(second):
                return ctime(second)[4:16]

        # make a new class for the file item
        if self.args.long:
            class __FileItem(LongFormatFileItem): ...
        else:
            class __FileItem(ShortFormatFileItem): ...
        __FileItem.fields = fields_list
        __FileItem.timeformater = formater
        __FileItem.consider_color = self.ok_for_color()
        self.FileItem = __FileItem

    def collect(self, name, dereference, basenameonly=True):
        '''
        collect file information according to the command line request,
        the result of the self.parse_args determines what to collect
        for example, when long format is request, many fields are
        required, on a simple ls, only the name is required, if sort
        by time is specified, time data will be collected.
        return a FileItem object
        '''
        infos = self.FileItem()
        infos.name = os.path.basename(name) if basenameonly else name
        if self.FileItem.fields:
            try:
                stat_info = os.stat(name, follow_symlinks=dereference)
            # lack of search permission through the path,
            # or the target of the symlink not exists
            except (PermissionError, FileNotFoundError) as e:
                print('%s: cannot access %s: %s'
                        % (os.path.basename(sys.argv[0]), name, e.args[1]), file=sys.stderr)
                for f in self.FileItem.fields: setattr(infos, f, 0)
                infos.failed = True
            else:
                for f in self.FileItem.fields: setattr(infos, f, getattr(stat_info, 'st_' + f))

                # getting infor for a symlink's target
                # only True when not 'follow_symlinks'
                if 'mode' in infos and stat.S_ISLNK(infos.mode):
                    target_path = os.readlink(name)
                    target = FileItem()
                    target.name = target_path
                    if target_path[0] != '/':
                        target_path = os.path.join(os.path.dirname(name), target_path)
                    try:
                        target_stat = os.stat(target_path, follow_symlinks=True)
                    except FileNotFoundError:
                        ...
                    else:
                        target.mode = target_stat.st_mode
                    infos.target = target
        return infos

    def sort(self, file_items):
        '''
        sort the list 'file_items' according to command line request
        that is, by -U (name), -X (name extension), -S (size), -t (time)
        -v (version) is not supported
        '''
        keymap = {
            'none'      : lambda x: str.lower(x.name),
            'extension' : lambda x: str.lower(x.name.split('.')[-1]),
            'size'      : lambda x: x.size,
            'time'      : lambda x: getattr(x, self.args.timestamptype),
        }
        key = keymap[self.args.sort]
        return sorted(file_items, key=key, reverse=self.args.reverse)

    def transform(self, file_items):
        '''
        convert blocks, uid, gid, size, time according to the command line arguments,
        convert numeric mode to string mode
        the conversion only done on a field when the field exists
        '''
        fields = self.FileItem.fields

        if not fields:
            return file_items

        for file in file_items:
            # handle the file that can not be stated
            if getattr(file, 'failed', False):
                for f in fields: setattr(file, f, '?')
                if 'mode' in fields: file.mode = '?' * 10
                continue

            # blocks
            if 'blocks' in fields: file.adjust_blocks(self.args.human_readable)
            # mode
            if 'mode' in fields:
                file.symbol_mode()
                # do it for the target of a symlink
                if getattr(file, 'target', None):
                    # if the target not exists, there will be no 'mode'
                    if getattr(file.target, 'mode', None):
                        file.target.symbol_mode()

            # uid, gid
            if not self.args.numeric_id:
                if 'uid' in fields: file.uid_to_name()
                if 'gid' in fields: file.gid_to_name()
            # size
            if self.args.human_readable and 'size' in fields:
                file.size = file.human_readable_size(file.size)
            # time
            timename = self.args.timestamptype
            if timename in fields: file.format_time(timename)

        return file_items

    def lay_out_oneperline(self, items):
        Y = len(items)
        X = 1
        width, widths, matrix = self.__lay_out(items, X, Y)
        return (matrix, widths)

    def lay_out(self, items, reserve_cols=0):
        '''
        lay out the file info (name and optionally other info) in the list of
        'file_items' according to the screen width, only necessary when long format
        listing is not the case.
        return a tuple contains a list of sequences (the matrix), and the column widths

        Math:
            Y * X >= T
            f(T, Y, sep) <= W
        which Y and X is the line count and column count respectively, T is the total
        items, W is the screen width

        we first build a matrix that contains data of columns, the reason for the columns
        is we need to calculate the width of a column.
        '''
        T = len(items)
        W = Term().cols() - reserve_cols

        # for performance sake, we set a start value of X
        start_X = 7
        X = start_X
        incre = 1   # 1 is to right, -1 is to left

        while True:
            # column hight, that is, line count
            Y = ceil(T / X)
            width, widths, matrix = self.__lay_out(items, X, Y)

            # exceed the width limet, two options:
            #   1. return
            #   2. begin to look back (left)
            if width > W:
                if X == 1:  # no more to try, can only return
                    return (matrix, widths)
                else:
                    if incre > 0:
                        if X == start_X:
                            incre = -1  # begin to look back
                        else:
                            return (prev_matrix, prev_widths)
            # not exceed, two options:
            # 1. return if row count is 1, or if in the way back
            # 2. continue to the next X in the same direction
            else:
                if Y == 1:  # fit into one row, no need to continue
                    return (matrix, widths)
                else:
                    if incre > 0:
                        prev_matrix = matrix
                        prev_widths = widths
                    else:
                        return (matrix, widths)
            X += incre

    def __lay_out(self, items, X, Y):
        matrix = []

        # list by column
        # multiple lists in the matrix, each represents a column
        if self.args.by_column:
            for i in range(X):
                matrix.append(items[(i * Y):((i + 1) * Y)])

        # list by line
        # at first, we get multiple lists in the matrix, each represents a line,
        # then, we transform this matrix into another matrix of multiple tuples,
        # each element of which represents a column
        else:
            for i in range(Y):
                matrix.append(items[(i * X):((i + 1) * X)])
            matrix = list(zip_longest(*matrix))

        # calculate the width of a single line
        # due to the zip_longest, the item may be None
        widths = []
        for g in matrix:
            # the whole column is empty, happens when
            # Y is 1, and X is greater than necessary.
            if not g:
                matrix[len(widths):] = []
                break

            nums = []
            # max width of inodes if needed
            if self.args.inode:
                nums.append(len(str(max(x.ino for x in g if x))))
            # max width of blocks if needed
            if self.args.size:
                nums.append(max(len(str(x.blocks)) for x in g if x))
            # max width of names
            nums.append(max(wcswidth(x.name) for x in g if x))
            widths.append(nums)
        # separator of inode, blocks and name is one space
        # separator of each file item is two spaces
        gen = (sum(nums) + (len(nums) - 1) for nums in widths)
        width = sum(gen) + (len(widths) - 1) * 2
        return width, widths, matrix

    def one_per_line(self):
        return self.args.oneperline and self.args.by_column

    def ok_for_color(self):
        '''determine if we shall show color in the output'''
        return sys.stdout.isatty() and self.args.color

    def colorize(self, *matrix):
        '''
        create color data for the file name in the matrix if necessary,
        the matrix is a list of lists. Change the file items in place.
        '''
        if self.ok_for_color():
            for group in matrix:
                for file in group:
                    try:
                        self.color.make(file)
                    # when a file can not be stated, it will not have a valid  mode attribute,
                    # and that will cause a KeyError exception in self.color.make.
                    except KeyError:
                        file.color = ''

    def print_matrix(self, matrix, widths):
        '''
        format the text and write it out.
        calculate the widths according to all file items.
        used for non-long format listing
        '''
        if not matrix: return

        formats = self.gen_short_format(widths)
        for line_items in zip_longest(*matrix, fillvalue=''):
            # due to the zip_longest, the item may be None
            text_list = [item.format(format) for item, format in zip(line_items, formats) if item]
            # no need to pad on the right for the last item in a row
            text_list[-1] = text_list[-1].rstrip()
            print('  '.join(text_list))

    def gen_short_format(self, widths):
        '''
        generate the format strings for short format listing,
        to format the output text.
        '''
        res = []
        for group in widths:
            format = []
            group, name_width = group[:-1], group[-1]
            for g in group:
                format.append('%%%ds' % g)          # right adjust for ino and blocks
            format.append('%%-%ds' % name_width)    # left adjust for name
            res.append(format)
        return res

    def gen_long_format(self, items, fields, args):
        '''
        generate the format strings for long format listing,
        to format the output text
        '''
        formats = []
        for f in fields:
            if   f == 'ino':
                formats.append('%%%ds' % max(len(str(x.ino)) for x in items))
            elif f == 'blocks':
                formats.append('%%%ds' % max(len(str(x.blocks)) for x in items))
            elif f == 'mode':
                formats.append('%s')
            elif f == 'nlink':
                formats.append('%%%ds' % max(len(str(x.nlink)) for x in items))
            elif f == 'uid':
                if args.numeric_id:
                    formats.append('%%%ds' % max(len(str(x.uid)) for x in items))
                else:
                    formats.append('%%-%ds' % max(len(str(x.uid)) for x in items))
            elif f == 'gid':
                if args.numeric_id:
                    formats.append('%%%ds' % max(len(str(x.gid)) for x in items))
                else:
                    formats.append('%%-%ds' % max(len(str(x.gid)) for x in items))
            elif f == 'size':
                formats.append('%%%ds' % max(len(str(x.size)) for x in items))
            elif f in ('atime', 'mtime', 'ctime'):
                formats.append('%%%ds' % max(len(getattr(x, f)) for x in items))
        return formats

    def print_long_format(self, items):
        '''
        format the text and write it out.
        calculate the widths according to all file items.
        used for long format listing
        '''
        if not items: return
        formats = self.gen_long_format(items, self.FileItem.fields, self.args)
        for item in items:
            print(item.format(formats))

    def list_dir(self, dir, num):
        '''
        list the content of a dir.
        dir is the directory to be listed,
        num is the index of this very directory among all directories to be listed,
        for determining whether to output a new line as a separator.
        '''
        if not self.args.recursive:
            try:
                files = os.listdir(dir)
            except PermissionError as ex:
                self.report_error(ex)
            else:
                files = self.filter_hidden(dir, files, forcehidden=False)
                if num: print()
                # when the directory is not the only 'thing' to list
                # we show its header
                if len(self.args.FILE) > 1: print(dir + ':')
                self.list_dir_ent_names(dir, files)
        else:
            for (thisdir, subs, files) in os.walk(dir, onerror=self.report_error):
                # filter the hidden files
                files = self.filter_hidden(dir, files, forcehidden=False)
                tmp_subs = self.filter_hidden(dir, subs)

                # sort the subs using the overall sorting method before further actions
                sub_paths = (os.path.join(thisdir, x) for x in tmp_subs)
                dir_items = [self.collect(path, self.args.dereference) for path in sub_paths]
                dir_items = self.sort(dir_items)
                subs.clear()
                subs.extend([x.name for x in dir_items])

                # when this is the first dir to list recursively
                # num will be zero at first, before this function return
                # there may be more than one directories to list, so
                # we make the num non-zero to ensure a separator been printed
                # for the subsequent directories
                if num: print()
                else: num = 1

                # when list recursively, always show the header
                print(thisdir + ':')
                self.list_dir_ent_names(thisdir, subs + files)

    def list_dir_ent_names(self, dir, files):
        '''
        fetch the blocks info for every directory entries
        in long format mode or when showing blocks is required (-s, --size)
        in order to show the sum total blocks before the directory entries.
        '''
        if self.args.long or self.args.size:
            need_removal = False
            if 'blocks' not in self.FileItem.fields:
                self.FileItem.fields.append('blocks')
                need_removal = True

        files = (os.path.join(dir, x) for x in files)
        file_items = [self.collect(name, self.args.dereference) for name in files]

        if self.args.long or self.args.size:
            # print the total blocks of a directory
            blocks = sum(x.blocks for x in file_items)
            blocks = adjust_blocks(blocks)
            print('total %s' % blocks)
            if need_removal: self.FileItem.fields.remove('blocks')

        file_items = self.sort(file_items)
        self.list_file_items(file_items)

    def filter_hidden(self, dir, names, forcehidden=True):
        '''
        the forcehidden is used to prevent descending into the . and ..,
        that is, hide the . and .. even -a is supplied.
        '''
        if self.args.all:           # -a, overwrites the -A
            if forcehidden:
                return names
            else:
                return ['.', '..'] + names
        elif self.args.almost_all:  # -A
            return names 
        else:                       # hide hidden file
            return [x for x in names if not x.startswith('.')]

    def report_error(self, obj):
        print('%s: cannot open directory %s: %s' % (
                os.path.basename(sys.argv[0]), obj.filename, obj.args[1]), file=sys.stderr)

    def list_file_items(self, file_items):
        '''
        given a list of file items, list their information
        '''
        if not file_items: return

        file_items = self.transform(file_items)
        self.colorize(file_items)
        if self.args.long:
            self.print_long_format(file_items)
        else:
            self.clean_short_format_fields()
            if self.one_per_line() or (not sys.stdout.isatty() and not self.args.multi):
                matrix, widths = self.lay_out_oneperline(file_items)
            else:
                matrix, widths = self.lay_out(file_items)
            self.print_matrix(matrix, widths)

    def clean_short_format_fields(self):
        '''
        called when do a short format listing,
        remove the fields not for listing but for sorting
        '''
        allowed = ('ino', 'blocks')
        fields = self.FileItem.fields
        self.FileItem.fields = [x for x in allowed if x in fields]

    def list_cmdline_items(self, names):
        '''
        given a list of file names, list their information
        used for listing the files listed on the command line.
        '''
        for name in names:
            try:
                os.stat(name, follow_symlinks=self.args.dereference)
            except FileNotFoundError as e:
                print('%s: cannot access %s: %s'
                        % (os.path.basename(sys.argv[0]), name, e.args[1]), file=sys.stderr)
                names.remove(name)

        file_items = [self.collect(name, self.args.dereference, basenameonly=False) for name in names]
        file_items = self.sort(file_items)
        self.list_file_items(file_items)

    def separate_dirs(self):
        '''
        separate the directories apart from all names in the sys.argv,
        return a tuple contains two lists of file items of files and dirs
        '''
        files   = []
        dirs    = []
        for name in self.args.FILE:
            try:
                os.stat(name, follow_symlinks=self.args.dereference)
            except FileNotFoundError as e:
                print('%s: cannot access %s: %s'
                        % (os.path.basename(sys.argv[0]), name, e.args[1]), file=sys.stderr)
                continue
            file_item = self.collect(name, self.args.dereference, basenameonly=False)
            if os.path.isdir(name):
                dirs.append(file_item)
            else:
                files.append(file_item)
        return (files, dirs)

    def list(self):
        '''
        interface to call for listing
        '''
        self.parse_args()
        if self.args.dir_only:
            self.list_cmdline_items(self.args.FILE)
        else:
            files, dirs = self.separate_dirs()
            self.list_file_items(self.sort(files))
            dirs  = self.sort(dirs)
            dir_names = [x.name for x in dirs]
            for num, dir in zip(range(len(dir_names)), dir_names):
                self.list_dir(dir, num)

def show_version():
    msg='''
ls (Python implementation of GNU ls of coreutils) 0.1
Copyright (C) 2015 Joshua Chen.
License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.

Written by Joshua Chen.
'''
    print(msg.strip())

def parse_args():
    from argparse import ArgumentParser, Action, RawDescriptionHelpFormatter

    class Specialarg(Action):
        def __call__(self, parser, namespace, values, option_string=None):
            if option_string == '-u':
                namespace.timestamptype = 'atime'
            elif option_string == '-c':
                namespace.timestamptype = 'ctime'
            elif option_string == '-U':
                namespace.sort = 'none'
            elif option_string == '-X':
                namespace.sort = 'extension'
            elif option_string == '-S':
                namespace.sort = 'size'
            elif option_string == '-t':
                namespace.sort = 'time'

    basename = os.path.basename(sys.argv[0])
    usage = basename + ' [OPTION]... [FILE]...'
    description = 'List information about the FILEs (the current directory by default).\n'
    description += 'Sort entries alphabetically if none of -cftuvSUX nor --sort.'
    epilog = '''
SIZE can be an integer optionally followed by one of the following units:
KB 1000, K 1024, MB 1000*1000, M 1024*1024, and so on for G, T, P, E, Z, Y.

Using color to distinguish file types is disabled both by default and
with --color=never.  With --color=auto, ls emits color codes only when
standard output is connected to a terminal.  The LS_COLORS environment
variable can change the settings.  Use the dircolors command to set it.

Exit status:
 0  if OK,
 1  if minor problems (e.g., cannot access subdirectory),
 2  if serious trouble (e.g., cannot access command-line argument).
'''
    parser = ArgumentParser(
                usage=usage,
                description=description,
                epilog=epilog,
                formatter_class=RawDescriptionHelpFormatter,
                add_help=False
            )
    parser.add_argument('FILE', help='file(s) to list', nargs='*')
    parser.add_argument('-a', '--all', help='the same as -A', action='store_true')
    parser.add_argument('-A', '--almost-all', help='do not list implied . and ..', action='store_true')
    parser.add_argument('-C', dest='by_column', help='list entries by columns', action='store_true', default=True)
    parser.add_argument('--color', metavar='WHEN', help='colorize the output.  WHEN defaults to ‘always’ or can be ‘never’ or ‘auto’.  More info below', default='never', nargs='?')
    parser.add_argument('-d', '--directory', dest='dir_only', help='list directory entries instead of contents, and do not dereference symbolic links', action='store_true')
    parser.add_argument('--full-time', help='like -l --time-style=full-iso', action='store_true')
    parser.add_argument('-h', '--human-readable', help='print sizes in human readable format (e.g., 1K 234M 2G)', action='store_true')
    parser.add_argument('-i', '--inode', help='print the index number of each file', action='store_true')
    parser.add_argument('-l', dest='long_format', help='use a long listing format', action='store_true')
    parser.add_argument('-L', '--dereference', help='when showing file information for a symbolic link, show information for the file the link references rather than for the link itself', action='store_true', default=False)
    parser.add_argument('-n', '--numeric-uid-gid', dest='numeric_id', help='like -l, but list numeric user and group IDs', action='store_true')
    parser.add_argument('-R', '--recursive', help='list subdirectories recursively', action='store_true')
    parser.add_argument('-u', help='with -lt: sort by, and show, access time with -l: show access time and sort by name otherwise: sort by access time', action=Specialarg, nargs=0)
    parser.add_argument('-c', help='with -lt: sort by, and show, ctime (time of last modification of file status information) with -l: show ctime and sort by name otherwise: sort by ctime', action=Specialarg, nargs=0)
    parser.add_argument('--sort', metavar='WORD', help='sort by WORD instead of name: none -U, extension -X, size -S, time -t, version -v (ignored)', default='none')
    parser.add_argument('-o', dest='no_group', help='like -l, but do not list group information', action='store_true')
    parser.add_argument('-g', dest='no_user', help='like -l, but do not list owner', action='store_true')
    parser.add_argument('-r', '--reverse', help='reverse order while sorting', action='store_true')
    parser.add_argument('-U', help='do not sort; list entries in directory order', action=Specialarg, nargs=0)
    parser.add_argument('-x', dest='by_column', help='list entries by lines instead of by columns', action='store_false')
    parser.add_argument('-X', help='sort alphabetically by entry extension', action=Specialarg, nargs=0)
    parser.add_argument('-S', help='sort by file size', action=Specialarg, nargs=0)
    parser.add_argument('-s', '--size', help='print the allocated size of each file, in blocks', action='store_true')
    parser.add_argument('-t', help='sort by modification time', action=Specialarg, nargs=0)
    parser.add_argument('-v', help='natural sort of (version) numbers within text (ignored)', action=Specialarg, nargs=0)
    parser.add_argument('-1', dest='oneperline', help='list one file per line', action='store_true', default=False)
    parser.add_argument('--multi', dest='multi', help='multiple items per line even stdout is not a terminal', action='store_true', default=False)
    parser.add_argument('--help', help='display this help and exit', action='help')
    parser.add_argument('--version', help='output version information and exit', action='store_true')
    return parser.parse_args()


if __name__ == '__main__':
    x = Ls()
    x.parse_args()
    if x.args.version:
        show_version()
        exit(0)
    try:
        x.list()
        exit(x.status)
    except KeyboardInterrupt:
        print()
        exit(1)
