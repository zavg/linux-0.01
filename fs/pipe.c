#include <signal.h>

#include <linux/sched.h>
#include <linux/mm.h>	/* for get_free_page */
#include <asm/segment.h>

int read_pipe(struct m_inode * inode, char * buf, int count)
{
	char * b=buf;

	while (PIPE_EMPTY(*inode)) {
		wake_up(&inode->i_wait);
		if (inode->i_count != 2) /* are there any writers left? */
			return 0;
		sleep_on(&inode->i_wait);
	}
	while (count>0 && !(PIPE_EMPTY(*inode))) {
		count --;
		put_fs_byte(((char *)inode->i_size)[PIPE_TAIL(*inode)],b++);
		INC_PIPE( PIPE_TAIL(*inode) );
	}
	wake_up(&inode->i_wait);
	return b-buf;
}
	
int write_pipe(struct m_inode * inode, char * buf, int count)
{
	char * b=buf;

	wake_up(&inode->i_wait);
	if (inode->i_count != 2) { /* no readers */
		current->signal |= (1<<(SIGPIPE-1));
		return -1;
	}
	while (count-->0) {
		while (PIPE_FULL(*inode)) {
			wake_up(&inode->i_wait);
			if (inode->i_count != 2) {
				current->signal |= (1<<(SIGPIPE-1));
				return b-buf;
			}
			sleep_on(&inode->i_wait);
		}
		((char *)inode->i_size)[PIPE_HEAD(*inode)] = get_fs_byte(b++);
		INC_PIPE( PIPE_HEAD(*inode) );
		wake_up(&inode->i_wait);
	}
	wake_up(&inode->i_wait);
	return b-buf;
}

int sys_pipe(unsigned long * fildes)
{
	struct m_inode * inode;
	struct file * f[2];
	int fd[2];
	int i,j;

	j=0;
	for(i=0;j<2 && i<NR_FILE;i++)
		if (!file_table[i].f_count)
			(f[j++]=i+file_table)->f_count++;
	if (j==1)
		f[0]->f_count=0;
	if (j<2)
		return -1;
	j=0;
	for(i=0;j<2 && i<NR_OPEN;i++)
		if (!current->filp[i]) {
			current->filp[ fd[j]=i ] = f[j];
			j++;
		}
	if (j==1)
		current->filp[fd[0]]=NULL;
	if (j<2) {
		f[0]->f_count=f[1]->f_count=0;
		return -1;
	}
	if (!(inode=get_pipe_inode())) {
		current->filp[fd[0]] =
			current->filp[fd[1]] = NULL;
		f[0]->f_count = f[1]->f_count = 0;
		return -1;
	}
	f[0]->f_inode = f[1]->f_inode = inode;
	f[0]->f_pos = f[1]->f_pos = 0;
	f[0]->f_mode = 1;		/* read */
	f[1]->f_mode = 2;		/* write */
	put_fs_long(fd[0],0+fildes);
	put_fs_long(fd[1],1+fildes);
	return 0;
}
