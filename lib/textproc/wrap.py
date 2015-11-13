'''
Author: Joshua Chen
Date: 2015-03-08
Location: Shenzhen
'''
class Wrap:
    '''
    wrap a given string according to the given limit.
    it mainly does two things:
    1. prevent word splitting at the end of the line.
    2. prevent the line from ending with a given set of chars
    3. prevent the first non-whitespace character of the next
       line be one of the characters: !:;,.?
    '''

    def __init__(self, line='', limit=0):
        self.line = line
        self.limit = limit
        self.wrap()

    def isSplitted(self, wordComponents):
        '''return True if word split occurred'''
        if (self.line[self.len - 1] in wordComponents
            and self.line[self.len] in wordComponents):
            return True
        else:
            return False

    def badEnd(self, badEndChars):
        if self.line[self.len - 1] in badEndChars:
            return True
        else:
            return False

    def badNextStart(self, badStartChars):
        text = self.line[self.len:].lstrip()
        if text and text[0] in badStartChars:
            return True
        else:
            return False

    def moveBack(self, start_index, ref):
        # not able to move back, not possible to wrap
        if start_index < 0:
            self.len = 0
            return
        # cut the line according to 'start_index', then revert the chars
        line = self.line[start_index::-1]
        hit = False
        for c, i in zip(line, range(1, start_index + 2)):
            if not c in ref:
                hit = True
                break
        if hit:
            self.len -= i
        else:
            self.len = 0

    def read(self):
        '''return the wrapped line'''
        return self.line[:self.len], self.line[self.len:]

    def wrap(self, line='', limit=0):
        '''actually do the wrapping'''

        if line:
            self.line = line
        else:
            line = self.line
        if limit:
            self.limit = limit
        else:
            limit = self.limit
        self.len = limit

        if len(line) <= limit:
            self.len = len(line)
            return self
        num = '0123456789'
        alpha = 'abcdefghijklmnopqrstuvwxyz'
        wordComponents = num + alpha + alpha.upper() + '_'
        badEndChars = '{[(<'
        badStartChars = '!:;,.?'

        while True:
            if self.isSplitted(wordComponents):
                self.moveBack(self.len - 2, wordComponents)

            # line characters exhausted, no need to continue
            if not self.len:
                self.len = limit
                return self

            if self.badEnd(badEndChars):
                self.moveBack(self.len - 2, badEndChars)

            # line characters exhausted, no need to continue
            if not self.len:
                self.len = limit
                return self

            if self.badNextStart(badStartChars):
                self.moveBack(self.len - 1, badStartChars)
                if not self.len:
                    self.len = limit
                    return self
            else:
                return self
