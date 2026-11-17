import posixpath
import sys
import tarfile

# App Store Connect takes no app whose uncompressed size reaches 4 GB, so a larger archive is not a build.
MAX_BYTES = 4 << 30
# An app bundle holds hundreds of files, so tens of thousands is no build either and costs the signer an inode each.
MAX_MEMBERS = 50_000


def refuse(message):
    escaped = message.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
    print(f'::error::{escaped}', file=sys.stderr)
    sys.exit(1)


def check(member):
    name = member.name
    # Every name reaches a log or a command line, where a line break would start a workflow command.
    if any(ord(char) < 32 or ord(char) == 127 for char in name):
        refuse(f'{name} carries a control character')
    if name.startswith('/'):
        refuse(f'{name} has an absolute path')
    normal = posixpath.normpath(name)
    if normal == '..' or normal.startswith('../'):
        refuse(f'{name} leaves the archive')
    if member.islnk():
        refuse(f'{name} is a hard link')
    # An iOS bundle carries no links, and resolving one safely means following every link before it.
    if member.issym():
        refuse(f'{name} is a symlink to {member.linkname}')
    if not (member.isfile() or member.isdir()):
        refuse(f'{name} is neither a file nor a directory')


def main():
    if len(sys.argv) != 3:
        refuse('usage: unpack_app.py <app.tar> <destination>')
    archive, destination = sys.argv[1:]
    with tarfile.open(archive) as tar:
        members = []
        total = 0
        # Each member is judged as it is read, before the reader moves past the size its header claims.
        for member in tar:
            check(member)
            total += member.size
            if total > MAX_BYTES:
                refuse(f'the archive unpacks to more than {MAX_BYTES} bytes, larger than an app can be')
            if len(members) == MAX_MEMBERS:
                refuse(f'the archive holds more than {MAX_MEMBERS} entries, more than an app has')
            members.append(member)
        tar.extractall(destination, members=members, filter='data')


if __name__ == '__main__':
    main()
